import Foundation
import NotchiumCore

/// The minimum persisted for a Shelf item: an opaque file reference and when it was added.
/// No file contents, sizes or other metadata are stored.
public struct ShelfRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let reference: Data
    public let addedAt: Date

    public init(id: UUID, reference: Data, addedAt: Date) {
        self.id = id
        self.reference = reference
        self.addedAt = addedAt
    }
}

public struct ResolvedShelfReference: Equatable, Sendable {
    public let url: URL
    /// The file moved/was renamed; the reference should be refreshed.
    public let isStale: Bool
    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

/// File references and their persistence for the Shelf. Items are held by reference:
/// nothing is copied.
@MainActor public protocol ShelfService: Sendable {
    func loadRecords() -> [ShelfRecord]
    func saveRecords(_ records: [ShelfRecord])
    func reference(for url: URL) -> Data?
    func resolve(_ reference: Data) -> ResolvedShelfReference?
    func fileExists(_ url: URL) -> Bool
    /// Balanced access for sandboxed builds; a no-op returning false when not sandboxed.
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

/// Bookmarks follow renames/moves; security scope is used when the process has it (Store
/// profile) and plain bookmarks otherwise (Developer ID profile).
@MainActor public final class RealShelfService: ShelfService {
    private let defaults: UserDefaults
    private let key = "shelf.items.v1"
    /// Security scope exists only inside the App Sandbox (Store profile).
    private let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func loadRecords() -> [ShelfRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ShelfRecord].self, from: data)) ?? []
    }

    public func saveRecords(_ records: [ShelfRecord]) {
        if records.isEmpty { defaults.removeObject(forKey: key); return }
        defaults.set(try? JSONEncoder().encode(records), forKey: key)
    }

    public func reference(for url: URL) -> Data? {
        let scoped: URL.BookmarkCreationOptions = isSandboxed ? [.withSecurityScope] : []
        return try? url.bookmarkData(options: scoped, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ reference: Data) -> ResolvedShelfReference? {
        var stale = false
        let attempts: [URL.BookmarkResolutionOptions] = isSandboxed
            ? [[.withSecurityScope, .withoutUI, .withoutMounting], [.withoutUI, .withoutMounting]]
            : [[.withoutUI, .withoutMounting]]
        for options in attempts {
            if let url = try? URL(resolvingBookmarkData: reference, options: options, relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                return ResolvedShelfReference(url: url, isStale: stale)
            }
        }
        return nil
    }

    public func fileExists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    public func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    public func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

/// In-memory references for tests and previews: a reference is the file path.
@MainActor public final class MockShelfService: ShelfService {
    public var records: [ShelfRecord] = []
    public var existingPaths: Set<String>
    public var movedPaths: [String: String] = [:]

    nonisolated public init(existingPaths: Set<String> = []) { self.existingPaths = existingPaths }

    public func loadRecords() -> [ShelfRecord] { records }
    public func saveRecords(_ records: [ShelfRecord]) { self.records = records }
    public func reference(for url: URL) -> Data? { Data(url.path.utf8) }
    public func resolve(_ reference: Data) -> ResolvedShelfReference? {
        guard let path = String(data: reference, encoding: .utf8) else { return nil }
        if let moved = movedPaths[path] { return .init(url: URL(fileURLWithPath: moved), isStale: true) }
        return existingPaths.contains(path) ? .init(url: URL(fileURLWithPath: path), isStale: false) : nil
    }
    public func fileExists(_ url: URL) -> Bool { existingPaths.contains(url.path) }
    public func startAccessing(_ url: URL) -> Bool { false }
    public func stopAccessing(_ url: URL) {}
}
