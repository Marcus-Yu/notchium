import Foundation
import NotchiumServices
import Observation

/// A small temporary workspace of file references (never copies). Newest first, bounded,
/// survives notch collapse and relaunch through bookmarks that are re-validated on restore.
@MainActor
@Observable
public final class ShelfModel {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public fileprivate(set) var url: URL
        public let addedAt: Date
        /// False once the file is missing (deleted, or its volume was ejected).
        public fileprivate(set) var isAvailable: Bool
        public var displayName: String { url.lastPathComponent }
    }

    public static let capacity = 24
    /// Items not touched for a week are dropped on restore rather than accumulating.
    public static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    public private(set) var items: [Item] = []

    @ObservationIgnored private let service: any ShelfService
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var references: [UUID: Data] = [:]
    @ObservationIgnored private var accessing: Set<UUID> = []

    public init(service: any ShelfService, now: @escaping () -> Date = Date.init) {
        self.service = service
        self.now = now
    }

    /// Rebuilds from persisted references: expired, unresolvable or missing files are dropped.
    public func restore() {
        let cutoff = now().addingTimeInterval(-Self.maximumAge)
        var restored: [Item] = []
        for record in service.loadRecords() where record.addedAt >= cutoff && restored.count < Self.capacity {
            guard let resolved = service.resolve(record.reference), service.fileExists(resolved.url),
                  !restored.contains(where: { Self.sameFile($0.url, resolved.url) }) else { continue }
            references[record.id] = resolved.isStale
                ? service.reference(for: resolved.url) ?? record.reference : record.reference
            if service.startAccessing(resolved.url) { accessing.insert(record.id) }
            restored.append(Item(id: record.id, url: resolved.url, addedAt: record.addedAt, isAvailable: true))
        }
        items = restored
        persist()
    }

    /// Adds by reference. A file already on the Shelf moves to the front instead of duplicating.
    /// Returns how many dropped files the Shelf now holds.
    @discardableResult
    public func add(_ urls: [URL]) -> Int {
        insert(urls).count
    }

    /// Exact accepted references let the composition model clean up only their source UI.
    @discardableResult
    func insert(_ urls: [URL]) -> [URL] {
        var accepted: [URL] = []
        // The URL is kept exactly as dropped; standardization is only used to spot duplicates.
        for url in urls.reversed() where url.isFileURL {
            guard service.fileExists(url) else { continue }
            if let index = items.firstIndex(where: { Self.sameFile($0.url, url) }) {
                items.insert(items.remove(at: index), at: 0)
                accepted.append(url)
                continue
            }
            guard service.fileExists(url), let reference = service.reference(for: url) else { continue }
            let item = Item(id: UUID(), url: url, addedAt: now(), isAvailable: true)
            references[item.id] = reference
            if service.startAccessing(url) { accessing.insert(item.id) }
            items.insert(item, at: 0)
            accepted.append(url)
        }
        while items.count > Self.capacity { release(items.removeLast()) }
        if !accepted.isEmpty { persist() }
        return accepted.filter { url in items.contains { Self.sameFile($0.url, url) } }
    }

    public func remove(_ id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        release(items.remove(at: index))
        persist()
    }

    public func clear() {
        items.forEach(release)
        items.removeAll()
        persist()
    }

    /// On demand (the Shelf page appearing), never polled: follows renames/moves through the
    /// bookmark and marks items whose file is gone.
    public func refreshAvailability() {
        var changed = false
        for index in items.indices {
            let item = items[index]
            if service.fileExists(item.url) {
                if !item.isAvailable { items[index].isAvailable = true; changed = true }
                continue
            }
            if let reference = references[item.id], let resolved = service.resolve(reference),
               service.fileExists(resolved.url) {
                items[index].url = resolved.url
                items[index].isAvailable = true
                references[item.id] = service.reference(for: resolved.url) ?? reference
            } else {
                items[index].isAvailable = false
            }
            changed = true
        }
        if changed { persist() }
    }

    private func release(_ item: Item) {
        references[item.id] = nil
        if accessing.remove(item.id) != nil { service.stopAccessing(item.url) }
    }

    private func persist() {
        service.saveRecords(items.compactMap { item in
            references[item.id].map { ShelfRecord(id: item.id, reference: $0, addedAt: item.addedAt) }
        })
    }

    private static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
