import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Small file previews for the notch, the Shelf and screenshots. Quick Look generates a
/// downsampled representation off the main actor (never a full-resolution decode), and a
/// bounded cache keeps at most a few dozen tiny images alive.
@MainActor
public final class NotchThumbnailCache {
    public static let shared = NotchThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    /// Keys generated per file, so invalidation is exact without enumerating NSCache.
    private var keysByPath: [String: Set<String>] = [:]
    private let generate: @Sendable (URL, CGSize, CGFloat) async -> NSImage?

    init(countLimit: Int = 48,
         generate: @escaping @Sendable (URL, CGSize, CGFloat) async -> NSImage? = NotchThumbnailCache.quickLook) {
        cache.countLimit = countLimit
        self.generate = generate
    }

    public func image(for url: URL, size: CGSize, scale: CGFloat = 2) async -> NSImage? {
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let running = inFlight[key] { return await running.value }
        let task = Task { [generate] in await generate(url, size, scale) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            cache.setObject(image, forKey: key as NSString)
            keysByPath[url.path, default: []].insert(key)
        }
        return image
    }

    /// Drops previews for a file that changed or went away.
    public func invalidate(_ url: URL) {
        keysByPath.removeValue(forKey: url.path)?.forEach { cache.removeObject(forKey: $0 as NSString) }
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
            image = await NotchThumbnailCache.shared.image(for: url, size: size)
        }
        .accessibilityHidden(true)
    }
}
