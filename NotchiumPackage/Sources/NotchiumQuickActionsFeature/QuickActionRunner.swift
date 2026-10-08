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
    public private(set) var succeeded: Set<UUID> = []
    public private(set) var shortcuts: [ExistingShortcut] = []
    public private(set) var discoveryError: String?
    public private(set) var refreshing = false
    private var preparedIcons: [UUID: (action: QuickAction, image: NSImage)] = [:]
    public let store: QuickActionStore
    public let workspace: any QuickActionWorkspace
    @ObservationIgnored private let shortcutService: any ShortcutService
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var acknowledgements: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var validated: [UUID: (QuickAction, Date)] = [:]
    @ObservationIgnored private var discoveredAt: Date?
    @ObservationIgnored private var discoveryTask: Task<[ExistingShortcut], any Error>?
    @ObservationIgnored private var discoveryGeneration = 0
    @ObservationIgnored private var executionGeneration = 0
    @ObservationIgnored private var executions: [UUID: Int] = [:]

    public init(store: QuickActionStore, workspace: any QuickActionWorkspace,
                shortcuts: any ShortcutService, notifications: NotificationCoordinator, clock: any AppClock) {
        self.store = store; self.workspace = workspace; shortcutService = shortcuts; self.clock = clock
        // Stage 20 feedback belongs to the tile. Quick Reminder still uses the shared coordinator.
    }
    public func refresh(force: Bool = true) async {
        await discover(force: force)
        for action in store.actions {
            guard !Task.isCancelled else { return }
            await validate(action, force: force)
        }
    }
    public func prepareHome() async {
        for action in store.pinned {
            guard !Task.isCancelled else { return }
            await prepareHomeAction(action)
        }
    }
    public func prepareHomeAction(_ action: QuickAction) async {
        if action.kind == .shortcut { await discover(force: false) }
        await validate(action, force: false)
    }
    /// Observable presentation state; native resource loading stays in the workspace adapter.
    public func icon(for action: QuickAction) -> NSImage? {
        guard let prepared = preparedIcons[action.id], prepared.action == action else { return nil }
        return prepared.image
    }
    private func discover(force: Bool) async {
        let now = await clock.now()
        if discoveryTask == nil, !force, let discoveredAt, now.timeIntervalSince(discoveredAt) < 60 { return }
        if discoveryTask == nil {
            discoveryGeneration += 1
            discoveryTask = Task { [shortcutService] in try await shortcutService.list() }
        }
        guard let task = discoveryTask else { return }
        let generation = discoveryGeneration
        refreshing = true
        defer {
            if generation == discoveryGeneration { refreshing = false; discoveryTask = nil }
        }
        do {
            let discovered = try await task.value
            try Task.checkCancellation()
            guard generation == discoveryGeneration else { return }
            shortcuts = discovered; discoveryError = nil; discoveredAt = now
        } catch is CancellationError { return }
        catch {
            guard generation == discoveryGeneration else { return }
            discoveryError = QuickActionFailure.discoveryFailed.localizedDescription
            // Back off failed discovery as well; opening Home must not repeatedly spawn a process.
            discoveredAt = now
        }
    }
    public func validate(_ candidate: QuickAction, force: Bool = true) async {
        guard let action = store.actions.first(where: { $0.id == candidate.id }) else { return }
        let now = await clock.now()
        if !force, let cached = validated[action.id], cached.0 == action, now.timeIntervalSince(cached.1) < 60 { return }
        do {
            let resolved: QuickAction
            if action.kind == .shortcut {
                guard discoveryError == nil else { throw QuickActionFailure.discoveryFailed }
                guard shortcuts.filter({ $0.id == action.shortcutID && $0.name == action.target }).count == 1 else {
                    throw QuickActionFailure.shortcutMissing
                }
                resolved = action
            } else { resolved = try await workspace.resolve(action) }
            try Task.checkCancellation()
            guard store.actions.contains(action) else { return }
            if resolved != action { try store.save(resolved) }
            await workspace.prepareIcon(for: resolved)
            try Task.checkCancellation()
            guard store.actions.contains(resolved) else { return }
            if let image = workspace.icon(for: resolved) {
                preparedIcons[action.id] = (resolved, image)
            } else { preparedIcons[action.id] = nil }
            unavailable[action.id] = nil
            validated[action.id] = (resolved, now)
        } catch is CancellationError { return }
        catch {
            guard store.actions.contains(action) else { return }
            unavailable[action.id] = error.localizedDescription
            validated[action.id] = (action, now)
        }
    }
    public func canRun(_ action: QuickAction) -> Bool {
        action.enabled && !running.contains(action.id) && unavailable[action.id] == nil
    }
    public func retry(_ action: QuickAction) async {
        if action.kind == .shortcut { await discover(force: true) }
        await validate(action)
        if canRun(action) { run(action) }
    }
    public func run(_ candidate: QuickAction) {
        guard let action = store.actions.first(where: { $0.id == candidate.id }) else { return }
        guard action.enabled, tasks[action.id] == nil else { return }
        executionGeneration += 1
        let generation = executionGeneration
        executions[action.id] = generation
        running.insert(action.id)
        succeeded.remove(action.id)
        tasks[action.id] = Task { [weak self] in
            guard let self else { return }
            let progress = Task { [weak self, clock] in
                do { try await clock.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled, self?.executions[action.id] == generation else { return }
                self?.showingProgress.insert(action.id)
            }
            defer {
                progress.cancel()
                if executions[action.id] == generation {
                    running.remove(action.id); showingProgress.remove(action.id); tasks[action.id] = nil
                    executions[action.id] = nil
                }
            }
            do {
                if action.kind == .shortcut {
                    guard let id = action.shortcutID else { throw QuickActionFailure.shortcutMissing }
                    try await shortcutService.run(ExistingShortcut(id: id, name: action.target))
                } else {
                    let resolved = try await workspace.resolve(action)
                    try Task.checkCancellation()
                    if resolved != action, store.actions.contains(action) { try store.save(resolved) }
                    try await workspace.open(resolved)
                }
                try Task.checkCancellation()
                guard executions[action.id] == generation else { return }
                unavailable[action.id] = nil
                acknowledge(action.id)
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, executions[action.id] == generation else { return }
                unavailable[action.id] = error.localizedDescription
                validated[action.id] = nil
                if action.kind == .shortcut { discoveredAt = nil }
            }
        }
    }
    private func acknowledge(_ id: UUID) {
        succeeded.insert(id)
        acknowledgements[id]?.cancel()
        acknowledgements[id] = Task { [weak self, clock] in
            do { try await clock.sleep(for: .milliseconds(1500)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.succeeded.remove(id); self?.acknowledgements[id] = nil
        }
    }
    public func cancel(_ id: UUID) { tasks[id]?.cancel() }
    public func stop() {
        discoveryGeneration += 1
        discoveryTask?.cancel(); discoveryTask = nil; refreshing = false
        for task in tasks.values { task.cancel() }
        for task in acknowledgements.values { task.cancel() }
        tasks.removeAll(); acknowledgements.removeAll()
        executions.removeAll()
        running.removeAll(); showingProgress.removeAll(); succeeded.removeAll()
    }
}
