import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation

/// Mirrors macOS Focus (on/off), announces changes once in the notch, and, while Focus is on,
/// asks the ActivityCoordinator to keep Notchium's routine notifications quiet.
/// Optionally turns Focus on for timer Focus sessions through the user's own Shortcuts.
@MainActor
@Observable
public final class FocusModeModel {
    public private(set) var isFocused: Bool?
    public private(set) var availability: FeatureAvailability = .unavailable(.permissionNotDetermined)
    public var reducesInterruptions: Bool {
        didSet {
            preferences.set(reducesInterruptions, forKey: Keys.reduce)
            applyPolicy()
        }
    }
    /// Run `focusOnShortcut` when a timer Focus session starts and `focusOffShortcut` when it ends.
    public var timerControlsFocus: Bool {
        didSet { preferences.set(timerControlsFocus, forKey: Keys.timerControls) }
    }
    public var focusOnShortcut: ExistingShortcut? {
        didSet { store(focusOnShortcut, key: Keys.onShortcut) }
    }
    public var focusOffShortcut: ExistingShortcut? {
        didSet { store(focusOffShortcut, key: Keys.offShortcut) }
    }
    public private(set) var availableShortcuts: [ExistingShortcut] = []
    public private(set) var shortcutError: String?

    @ObservationIgnored private let service: any FocusService
    @ObservationIgnored private let activities: ActivityCoordinator
    @ObservationIgnored private let shortcuts: any ShortcutService
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Only a Focus this model turned on is turned off again; a Focus the user chose stays.
    @ObservationIgnored private(set) var turnedOnByTimer = false

    static let key = "focus.mode"

    private enum Keys {
        static let reduce = "notchium.focus.reduceInterruptions.v1"
        static let timerControls = "notchium.focus.timerControlsFocus.v1"
        static let onShortcut = "notchium.focus.onShortcut.v1"
        static let offShortcut = "notchium.focus.offShortcut.v1"
    }

    public init(service: any FocusService, activities: ActivityCoordinator, shortcuts: any ShortcutService,
                preferences: UserDefaults = .standard) {
        self.service = service
        self.activities = activities
        self.shortcuts = shortcuts
        self.preferences = preferences
        reducesInterruptions = preferences.object(forKey: Keys.reduce) as? Bool ?? true
        timerControlsFocus = preferences.bool(forKey: Keys.timerControls)
        focusOnShortcut = Self.load(Keys.onShortcut, from: preferences)
        focusOffShortcut = Self.load(Keys.offShortcut, from: preferences)
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self, service] in
            for await snapshot in await service.updates() {
                guard !Task.isCancelled, let self else { return }
                self.receive(snapshot)
            }
        }
    }

    public func stop() {
        task?.cancel(); task = nil
        activities.reducesInterruptions = false
        activities.notifications.dismiss(coalescingKey: Self.key)
    }

    func receive(_ snapshot: FocusSnapshot) {
        availability = snapshot.availability
        let previous = isFocused
        isFocused = snapshot.isFocused
        applyPolicy()
        // The first answer is state, not a change: nothing is announced at launch.
        guard let previous, let now = snapshot.isFocused, previous != now else { return }
        activities.notifications.present(NotchNotification(
            kind: .focusModeChanged, coalescingKey: Self.key, action: .none, presentationStyle: .compact,
            content: .compact(.init(glyph: .symbol(now ? "moon.fill" : "moon"), title: now ? "Focus On" : "Focus Off",
                                    showsTitle: false, trailing: .text(now ? "Focus" : "Focus Off"),
                                    tint: now ? .focus : .muted))))
    }

    private func applyPolicy() {
        activities.reducesInterruptions = reducesInterruptions && isFocused == true
    }

    // MARK: Shortcuts

    public var canControlFocus: Bool { timerControlsFocus && focusOnShortcut != nil && focusOffShortcut != nil }

    public func refreshShortcuts() async {
        do {
            availableShortcuts = try await shortcuts.list()
            shortcutError = nil
        } catch {
            shortcutError = (error as? LocalizedError)?.errorDescription ?? "Couldn’t load shortcuts."
        }
    }

    private func run(_ shortcut: ExistingShortcut?) {
        guard let shortcut else { return }
        Task { [weak self, shortcuts] in
            do { try await shortcuts.run(shortcut) } catch {
                self?.shortcutError = (error as? LocalizedError)?.errorDescription ?? "The Focus shortcut failed."
            }
        }
    }

    private func store(_ shortcut: ExistingShortcut?, key: String) {
        guard let shortcut else { preferences.removeObject(forKey: key); return }
        preferences.set([shortcut.id.uuidString, shortcut.name], forKey: key)
    }

    private static func load(_ key: String, from preferences: UserDefaults) -> ExistingShortcut? {
        guard let parts = preferences.stringArray(forKey: key), parts.count == 2,
              let id = UUID(uuidString: parts[0]) else { return nil }
        return ExistingShortcut(id: id, name: parts[1])
    }
}

extension FocusModeModel: FocusSessionFocusControlling {
    public func focusSessionBegan() {
        // Focus the user already turned on is theirs; it is neither touched now nor turned off later.
        guard canControlFocus, isFocused != true, !turnedOnByTimer else { return }
        turnedOnByTimer = true
        run(focusOnShortcut)
    }

    public func focusSessionEnded() {
        guard turnedOnByTimer else { return }
        turnedOnByTimer = false
        run(focusOffShortcut)
    }
}
