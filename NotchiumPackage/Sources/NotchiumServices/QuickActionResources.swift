import Foundation
import NotchiumCore

/// Bookmark and filesystem work stays off the UI actor. No file contents are read.
actor QuickActionResources {
    private let sandboxed: Bool
    init(sandboxed: Bool) { self.sandboxed = sandboxed }

    func reference(_ url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if sandboxed && !accessing { throw QuickActionFailure.accessDenied }
        return try url.bookmarkData(options: sandboxed ? [.withSecurityScope, .securityScopeAllowOnlyReadAccess] : [],
                                    includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    func resolve(_ action: QuickAction, applicationFallback: URL?) throws -> (QuickAction, URL) {
        var stale = false
        let options: URL.BookmarkResolutionOptions = sandboxed
            ? [.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting]
        let bookmarked = action.bookmark.flatMap {
            try? URL(resolvingBookmarkData: $0, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        // Launch Services is authoritative for an app moved/reinstalled with the same bundle ID.
        guard let url = bookmarked ?? applicationFallback, url.isFileURL else { throw QuickActionFailure.unavailable }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if sandboxed && !accessing && action.kind != .application { throw QuickActionFailure.accessDenied }
        var resolvedURL = url
        if !FileManager.default.fileExists(atPath: url.path), let applicationFallback {
            resolvedURL = applicationFallback
        }
        if action.kind == .application, let expected = action.bundleIdentifier,
           Bundle(url: resolvedURL)?.bundleIdentifier != expected {
            guard let applicationFallback, Bundle(url: applicationFallback)?.bundleIdentifier == expected else {
                throw QuickActionFailure.unavailable
            }
            resolvedURL = applicationFallback
        }
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else { throw QuickActionFailure.unavailable }
        let values = try resolvedURL.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey, .isReadableKey])
        guard values.isReadable != false else { throw QuickActionFailure.accessDenied }
        if action.kind == .folder && values.isDirectory != true { throw QuickActionFailure.unavailable }
        if action.kind == .file && values.isDirectory == true { throw QuickActionFailure.unavailable }
        if action.kind == .application && values.isApplication != true { throw QuickActionFailure.unavailable }
        var updated = action
        updated.target = resolvedURL.absoluteString
        if stale || bookmarked == nil || resolvedURL != url { updated.bookmark = try reference(resolvedURL) }
        return (updated, resolvedURL)
    }
}
