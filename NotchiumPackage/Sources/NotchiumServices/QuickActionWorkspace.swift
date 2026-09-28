import AppKit
import NotchiumCore
import UniformTypeIdentifiers

@MainActor public protocol QuickActionWorkspace: Sendable {
    func chooseTarget(for kind: QuickActionKind) async throws -> QuickAction?
    func resolve(_ action: QuickAction) throws -> QuickAction
    func open(_ action: QuickAction) async throws
    func icon(for action: QuickAction) -> NSImage?
    func openReminderPrivacy()
}

@MainActor public final class NativeQuickActionWorkspace: QuickActionWorkspace {
    private let workspace: NSWorkspace
    public init(workspace: NSWorkspace = .shared) { self.workspace = workspace }
    public func chooseTarget(for kind: QuickActionKind) async throws -> QuickAction? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = kind == .folder
        panel.canChooseFiles = kind != .folder
        panel.title = "Choose \(kind.title)"
        if kind == .application { panel.allowedContentTypes = [.applicationBundle] }
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
        return QuickAction(kind: kind, displayName: url.deletingPathExtension().lastPathComponent,
                           target: url.absoluteString, bookmark: bookmark)
    }
    private func resource(_ action: QuickAction) throws -> (URL, Bool) {
        guard let bookmark = action.bookmark else { throw QuickActionFailure.unavailable }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }
    public func resolve(_ action: QuickAction) throws -> QuickAction {
        if action.kind == .url {
            guard QuickAction.validatedWebURL(action.target) != nil else { throw QuickActionFailure.invalidURL }
            return action
        }
        if action.kind == .shortcut { return action }
        let (url, stale) = try resource(action)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { throw QuickActionFailure.unavailable }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey])
        if action.kind == .folder && values.isDirectory != true { throw QuickActionFailure.unavailable }
        if action.kind == .application && values.isApplication != true { throw QuickActionFailure.unavailable }
        var updated = action
        updated.target = url.absoluteString
        if stale {
            updated.bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return updated
    }
    public func open(_ action: QuickAction) async throws {
        if action.kind == .url {
            guard let url = QuickAction.validatedWebURL(action.target) else { throw QuickActionFailure.invalidURL }
            guard workspace.open(url) else { throw QuickActionFailure.unavailable }
            return
        }
        let updated = try resolve(action)
        let (url, _) = try resource(updated)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if action.kind == .application {
            _ = try await workspace.openApplication(at: url, configuration: .init())
        } else {
            guard workspace.open(url) else { throw QuickActionFailure.unavailable }
        }
    }
    public func icon(for action: QuickAction) -> NSImage? {
        guard action.kind != .url, action.kind != .shortcut,
              let (url, _) = try? resource(action) else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return workspace.icon(forFile: url.path)
    }
    public func openReminderPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            workspace.open(url)
        }
    }
}
