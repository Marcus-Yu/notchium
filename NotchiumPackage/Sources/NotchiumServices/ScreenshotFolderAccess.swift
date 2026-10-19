import AppKit
import Foundation

/// A selected folder is a scoped file grant, never a blanket Files & Folders permission.
@MainActor public final class ScreenshotFolderAccess {
    public static let key = "notchium.screenshots.folder.v1"
    private let defaults: UserDefaults
    private let sandboxed: Bool
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    public var hasSelection: Bool { defaults.object(forKey: Self.key) != nil }

    public func resolve() -> URL? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        var stale = false
        let options: URL.BookmarkResolutionOptions = sandboxed
            ? [.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting]
        guard let url = try? URL(resolvingBookmarkData: data, options: options,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { try? save(url) }
        return url
    }

    public func choose() async throws -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose your screenshot folder"
        panel.message = "Choose the folder where macOS saves screenshots. Notchium watches new screenshot files in this folder; it does not record your screen."
        panel.prompt = "Allow Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.collectionBehavior.insert(.fullScreenAuxiliary)
        let result = await panel.begin()
        guard result == .OK, let url = panel.url else { return false }
        try save(url)
        return true
    }

    private func save(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let options: URL.BookmarkCreationOptions = sandboxed
            ? [.withSecurityScope, .securityScopeAllowOnlyReadAccess] : []
        defaults.set(try url.bookmarkData(options: options, includingResourceValuesForKeys: nil,
                                        relativeTo: nil), forKey: Self.key)
    }
}
