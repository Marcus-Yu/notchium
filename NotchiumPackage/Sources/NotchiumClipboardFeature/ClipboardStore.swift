import Foundation
import NotchiumServices

/// A stored clipboard entry. Text and links are kept inline; image bytes live in a separate
/// file (only the thumbnail is held in memory).
public struct ClipboardItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ClipboardItemKind
    public var text: String?
    public var url: URL?
    public var fileURLs: [URL]?
    public var thumbnail: Data?
    public var pixelSize: CGSize?
    public var capturedAt: Date
    public var isPinned: Bool
    public let fingerprint: String

    init(id: UUID = UUID(), content: ClipboardContent, capturedAt: Date) {
        self.id = id
        kind = content.kind
        self.capturedAt = capturedAt
        isPinned = false
        fingerprint = content.fingerprint
        switch content {
        case let .text(value): text = value
        case let .url(value): url = value
        case let .image(_, thumbnail, size):
            self.thumbnail = thumbnail
            pixelSize = size
        case let .files(urls): fileURLs = urls
        }
    }

    /// One line for the list: first non-empty line of text, the host and path of a link, the
    /// file name(s), or the image size.
    public var preview: String {
        switch kind {
        case .text:
            let line = text?.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return line.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        case .url:
            guard let url else { return "" }
            let host = url.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
            let path = url.path() == "/" ? "" : url.path()
            return host + path
        case .file:
            let names = fileURLs?.map(\.lastPathComponent) ?? []
            return names.count > 1 ? "\(names[0]) +\(names.count - 1)" : (names.first ?? "")
        case .image:
            guard let pixelSize else { return "Image" }
            return "Image · \(Int(pixelSize.width)) × \(Int(pixelSize.height))"
        }
    }

    /// Words searched by the filter.
    public var searchText: String {
        switch kind {
        case .text: text ?? ""
        case .url: url?.absoluteString ?? ""
        case .file: fileURLs?.map(\.lastPathComponent).joined(separator: " ") ?? ""
        case .image: "image"
        }
    }
}

public protocol ClipboardStoring: AnyObject, Sendable {
    func loadItems() -> [ClipboardItem]
    func saveItems(_ items: [ClipboardItem])
    func saveImage(_ png: Data, id: UUID)
    func loadImage(id: UUID) -> Data?
    func removeImages(except ids: Set<UUID>)
    /// Drain ordered writes before application teardown. In-memory stores need no barrier.
    func flush()
}

public extension ClipboardStoring { func flush() {} }

/// Application Support/Notchium/Clipboard: one JSON index plus one PNG per image. Local only.
public final class FileClipboardStore: ClipboardStoring, @unchecked Sendable {
    private let directory: URL
    // All disk work and the image index are serialized here. Synchronous reads/barriers
    // observe every preceding write; routine saves never encode or scan on MainActor.
    private let queue = DispatchQueue(label: "notchium.clipboard.store", qos: .utility)
    private var imageIDs: Set<UUID>?

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchium/Clipboard", isDirectory: true)
    }

    private var index: URL { directory.appendingPathComponent("history.json") }
    private func imageURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).png") }

    public func loadItems() -> [ClipboardItem] {
        queue.sync {
            guard let data = try? Data(contentsOf: index) else { return [] }
            return (try? JSONDecoder().decode([ClipboardItem].self, from: data)) ?? []
        }
    }

    public func saveItems(_ items: [ClipboardItem]) {
        queue.async { [self] in
            guard let data = try? JSONEncoder().encode(items) else { return }
            ensureDirectory()
            try? data.write(to: index, options: [.atomic])
        }
    }

    public func saveImage(_ png: Data, id: UUID) {
        queue.async { [self] in
            ensureDirectory()
            try? png.write(to: imageURL(id), options: [.atomic])
            if imageIDs != nil { imageIDs?.insert(id) }
        }
    }

    public func loadImage(id: UUID) -> Data? {
        queue.sync { try? Data(contentsOf: imageURL(id)) }
    }

    public func removeImages(except ids: Set<UUID>) {
        queue.async { [self] in
            if imageIDs == nil {
                guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                else { return }
                imageIDs = Set(files.filter { $0.pathExtension == "png" }.compactMap {
                    UUID(uuidString: $0.deletingPathExtension().lastPathComponent)
                })
            }
            for id in imageIDs!.subtracting(ids) {
                do {
                    try FileManager.default.removeItem(at: imageURL(id))
                    imageIDs?.remove(id)
                } catch {
                    // Missing files are already removed. Keep real failures for a later cleanup.
                    if !FileManager.default.fileExists(atPath: imageURL(id).path) { imageIDs?.remove(id) }
                }
            }
        }
    }

    public func flush() { queue.sync {} }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

public final class InMemoryClipboardStore: ClipboardStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ClipboardItem] = []
    private var images: [UUID: Data] = [:]

    public init(items: [ClipboardItem] = []) { self.items = items }

    public var imageIDs: Set<UUID> { lock.withLock { Set(images.keys) } }

    public func loadItems() -> [ClipboardItem] { lock.withLock { items } }
    public func saveItems(_ items: [ClipboardItem]) { lock.withLock { self.items = items } }
    public func saveImage(_ png: Data, id: UUID) { lock.withLock { images[id] = png } }
    public func loadImage(id: UUID) -> Data? { lock.withLock { images[id] } }
    public func removeImages(except ids: Set<UUID>) { lock.withLock { images = images.filter { ids.contains($0.key) } } }
}
