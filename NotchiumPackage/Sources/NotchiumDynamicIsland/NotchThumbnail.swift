import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Small file previews for the notch, the Shelf and screenshots. Quick Look generates a
/// downsampled representation off the main actor (never a full-resolution decode), and a
/// bounded cache keeps at most a few dozen tiny images alive.
@MainActor
public final class NotchThumbnailCache {
    public static let shared = NotchThumbnailCache()

    private struct Key: Hashable {
        let url: URL
        let width: CGFloat
        let height: CGFloat
        let scale: CGFloat
    }
    private struct Request {
        let id = UUID()
        let task: Task<NSImage?, Never>
    }
    // A bounded LRU includes the key bookkeeping. NSCache eviction previously left an
    // ever-growing path index behind during long sessions.
    private var cache: [Key: NSImage] = [:]
    private var recency: [Key] = []
    private var inFlight: [Key: Request] = [:]
    private let countLimit: Int
    private let generate: @Sendable (URL, CGSize, CGFloat) async -> NSImage?

    init(countLimit: Int = 48,
         generate: @escaping @Sendable (URL, CGSize, CGFloat) async -> NSImage? = NotchThumbnailCache.quickLook) {
        self.countLimit = max(1, countLimit)
        self.generate = generate
    }

    public func image(for url: URL, size: CGSize, scale: CGFloat = 2) async -> NSImage? {
        let key = Key(url: url.standardizedFileURL, width: size.width, height: size.height, scale: scale)
        if let cached = cache[key] {
            touch(key)
            return cached
        }
        if let running = inFlight[key] {
            let image = await running.task.value
            return running.task.isCancelled ? nil : image
        }
        let request = Request(task: Task { [generate] in await generate(url, size, scale) })
        inFlight[key] = request
        let image = await request.task.value
        // Invalidation may have removed this request and started a replacement for the
        // same path. The old callback owns neither the cache nor the replacement task.
        guard inFlight[key]?.id == request.id, !request.task.isCancelled else { return nil }
        inFlight[key] = nil
        if let image {
            cache[key] = image
            touch(key)
            while recency.count > countLimit { cache[recency.removeFirst()] = nil }
        }
        return image
    }

    /// Drops previews for a file that changed or went away.
    public func invalidate(_ url: URL) {
        let url = url.standardizedFileURL
        for key in cache.keys.filter({ $0.url == url }) { cache[key] = nil }
        recency.removeAll { $0.url == url }
        for key in inFlight.keys.filter({ $0.url == url }) {
            inFlight.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    nonisolated static func quickLook(_ url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale,
                                                   representationTypes: [.thumbnail, .icon])
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation.map { UncheckedImage($0.nsImage) }?.image)
            }
        }
    }
}

/// NSImage is not Sendable; a generated thumbnail is immutable once handed over.
private struct UncheckedImage: @unchecked Sendable {
    let image: NSImage
    init(_ image: NSImage) { self.image = image }
}

/// Loads its preview asynchronously; a quiet placeholder until then, or if the file vanished.
public struct NotchThumbnailView: View {
    let url: URL
    let size: CGSize
    var cornerRadius: CGFloat = 4
    @State private var image: NSImage?

    public init(url: URL, size: CGSize, cornerRadius: CGFloat = 4) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.1))
                    .overlay {
                        Image(systemName: "doc")
                            .font(.system(size: min(size.width, size.height) * 0.42))
                            .foregroundStyle(.white.opacity(0.45))
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: image != nil)
        .task(id: url) {
            let loaded = await NotchThumbnailCache.shared.image(for: url, size: size)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .accessibilityHidden(true)
    }
}
