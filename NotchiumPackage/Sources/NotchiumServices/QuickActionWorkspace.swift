import AppKit
import NotchiumCore
import UniformTypeIdentifiers

@MainActor public protocol QuickActionWorkspace: Sendable {
    func chooseTarget(for kind: QuickActionKind) async throws -> QuickAction?
    func resolve(_ action: QuickAction) async throws -> QuickAction
    func open(_ action: QuickAction) async throws
    /// Cache access only; render passes must not resolve bookmarks or load icons.
    func icon(for action: QuickAction) -> NSImage?
    func prepareIcon(for action: QuickAction) async
    func openReminderPrivacy()
}

public extension QuickActionWorkspace {
    func prepareIcon(for action: QuickAction) async {}
}

@MainActor public final class NativeQuickActionWorkspace: QuickActionWorkspace {
    private let workspace: NSWorkspace
    private let resources: QuickActionResources
    private var icons: [UUID: (QuickAction, NSImage)] = [:]
    private var resolvedURLs: [UUID: (QuickAction, URL)] = [:]
    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        resources = QuickActionResources(sandboxed: ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
    }
    public func chooseTarget(for kind: QuickActionKind) async throws -> QuickAction? {
        guard [.application, .file, .folder].contains(kind) else { return nil }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = kind == .folder
        panel.canChooseFiles = kind != .folder
        panel.title = "Choose \(kind.title)"
        if kind == .application {
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        }
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        let bookmark = try await resources.reference(url)
        return QuickAction(kind: kind, displayName: url.deletingPathExtension().lastPathComponent,
                           target: url.absoluteString, bookmark: bookmark,
                           bundleIdentifier: kind == .application ? Bundle(url: url)?.bundleIdentifier : nil)
    }
    public func resolve(_ action: QuickAction) async throws -> QuickAction {
        switch action.kind {
        case .url:
            guard let url = QuickAction.validatedURL(action.target) else { throw QuickActionFailure.invalidURL }
            guard workspace.urlForApplication(toOpen: url) != nil else { throw QuickActionFailure.unavailable }
            return action
        case .shortcut: return action
        case .systemAction:
            guard let native = NativeHomeAction(rawValue: action.target), let url = systemURL(native) else {
                throw QuickActionFailure.unavailable
            }
            if native != .systemSettings && !FileManager.default.fileExists(atPath: url.path) {
                throw QuickActionFailure.unavailable
            }
            return action
        case .application, .file, .folder:
            let fallback = action.kind == .application ? action.bundleIdentifier.flatMap {
                workspace.urlForApplication(withBundleIdentifier: $0)
            } : nil
            let (resolved, url) = try await resources.resolve(action, applicationFallback: fallback)
            resolvedURLs[action.id] = (resolved, url)
            return resolved
        }
    }
    public func open(_ action: QuickAction) async throws {
        if action.kind == .url {
            guard let url = QuickAction.validatedURL(action.target) else { throw QuickActionFailure.invalidURL }
            guard workspace.open(url) else { throw QuickActionFailure.unavailable }
            return
        }
        if action.kind == .systemAction {
            guard let native = NativeHomeAction(rawValue: action.target), let url = systemURL(native), workspace.open(url) else {
                throw QuickActionFailure.unavailable
            }
            return
        }
        guard [.application, .file, .folder].contains(action.kind) else {
            throw QuickActionFailure.unavailable
        }
        let resolved = try await resolve(action)
        guard let url = resolvedURLs[resolved.id]?.1 else { throw QuickActionFailure.unavailable }
        // Runner resolves immediately before opening; hold the scope through Launch Services' completion.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if action.kind == .application {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await workspace.openApplication(at: url, configuration: configuration)
        } else {
            _ = try await workspace.open(url, configuration: .init())
        }
    }
    public func prepareIcon(for action: QuickAction) async {
        guard action.symbol == nil, [.application, .file, .folder].contains(action.kind),
              icons[action.id]?.0 != action, resolvedURLs[action.id]?.0 == action,
              let url = resolvedURLs[action.id]?.1 else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        icons[action.id] = (action, workspace.icon(forFile: url.path))
    }
    public func icon(for action: QuickAction) -> NSImage? {
        guard icons[action.id]?.0 == action else { return nil }
        return icons[action.id]?.1
    }
    private func systemURL(_ action: NativeHomeAction) -> URL? {
        switch action {
        case .systemSettings: workspace.urlForApplication(withBundleIdentifier: "com.apple.systempreferences")
        case .downloads: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .desktop: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        }
    }
    public func openReminderPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            workspace.open(url)
        }
    }
}
