import AppKit
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumPersistence
import NotchiumServices
import Observation

@MainActor @Observable public final class QuickActionRunner {
    public private(set) var unavailable: [UUID: String] = [:]
    public private(set) var running: Set<UUID> = []
    public private(set) var showingProgress: Set<UUID> = []
    public private(set) var shortcuts: [ExistingShortcut] = []
    public private(set) var discoveryError: String?
    public private(set) var refreshing = false
    public let store: QuickActionStore
    public let workspace: any QuickActionWorkspace
    @ObservationIgnored private let shortcutService: any ShortcutService
    @ObservationIgnored private let notifications: NotificationCoordinator
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(store: QuickActionStore, workspace: any QuickActionWorkspace,
                shortcuts: any ShortcutService, notifications: NotificationCoordinator, clock: any AppClock) {
        self.store = store; self.workspace = workspace; shortcutService = shortcuts
        self.notifications = notifications; self.clock = clock
    }
    public func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do { shortcuts = try await shortcutService.list(); discoveryError = nil }
        catch is CancellationError { return }
        catch { discoveryError = QuickActionFailure.discoveryFailed.localizedDescription }
        for action in store.actions { validate(action) }
    }
    public func validate(_ action: QuickAction) {
        do {
            if action.kind == .shortcut {
                guard discoveryError == nil else { throw QuickActionFailure.discoveryFailed }
                guard shortcuts.filter({ $0.id == action.shortcutID && $0.name == action.target }).count == 1 else { throw QuickActionFailure.shortcutMissing }
            } else {
                let resolved = try workspace.resolve(action)
                if resolved != action { try store.save(resolved) }
            }
            unavailable[action.id] = nil
        } catch { unavailable[action.id] = error.localizedDescription }
    }
    public func run(_ action: QuickAction) {
        guard action.enabled, tasks[action.id] == nil else { return }
        running.insert(action.id)
        tasks[action.id] = Task { [weak self] in
            guard let self else { return }
            let progress = Task { [weak self, clock] in
                do { try await clock.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.showingProgress.insert(action.id)
            }
            defer {
                progress.cancel()
                running.remove(action.id); showingProgress.remove(action.id); tasks[action.id] = nil
            }
            do {
                if action.kind == .shortcut {
                    guard let id = action.shortcutID else { throw QuickActionFailure.shortcutMissing }
                    try await shortcutService.run(ExistingShortcut(id: id, name: action.target))
                }
                else {
                    let resolved = try workspace.resolve(action)
                    if resolved != action { try store.save(resolved) }
                    try await workspace.open(resolved)
                }
                try Task.checkCancellation()
                unavailable[action.id] = nil
                notifications.present(.feedback("\(action.displayName) \(action.kind == .shortcut ? "Completed" : "Opened")", kind: .actionSucceeded,
                    key: "action.\(action.id)"))
            } catch is CancellationError { }
            catch {
                unavailable[action.id] = error.localizedDescription
                notifications.present(.feedback("Action Unavailable — Edit in Settings", kind: .actionFailed,
                    key: "action.\(action.id)"))
            }
        }
    }
    public func cancel(_ id: UUID) { tasks[id]?.cancel() }
    public func stop() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll(); running.removeAll(); showingProgress.removeAll()
    }
}
