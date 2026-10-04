import AppKit
import NotchiumCore
import NotchiumDynamicIsland
import Observation
import SwiftUI

/// What the collapsed notch leads with while the timer runs and Music is playing.
public enum CollapsedTimerPreference: String, CaseIterable, Identifiable, Sendable {
    case timer, music
    public var id: String { rawValue }
    public var title: String { self == .timer ? "Timer" : "Music" }
}

/// Optional macOS Focus coupling for Focus sessions (Shortcuts-based, see FocusModeModel).
@MainActor public protocol FocusSessionFocusControlling: AnyObject {
    func focusSessionBegan()
    func focusSessionEnded()
}

/// Owns the timer, its persisted state and the session history. The visible time is derived
/// from the deadline; the only scheduled work is one sleep until the next deadline.
@MainActor
@Observable
public final class PomodoroModel {
    public private(set) var state: PomodoroState
    public private(set) var records: [FocusSessionRecord]
    public var configuration: PomodoroConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            preferences.set(try? JSONEncoder().encode(configuration), forKey: Keys.configuration)
            publishActivity()
        }
    }
    public var collapsedPreference: CollapsedTimerPreference {
        didSet {
            guard collapsedPreference != oldValue else { return }
            preferences.set(collapsedPreference.rawValue, forKey: Keys.collapsed)
            // Presentation only: the same activity identity re-ranks; the timer is untouched.
            publishActivity()
        }
    }
    public var completionSound: PomodoroSound {
        didSet {
            guard completionSound != oldValue else { return }
            preferences.set(completionSound.rawValue, forKey: Keys.selectedSound)
            soundPlayer.stop()
        }
    }
    public private(set) var isPageVisible = false
    /// A paused timer leaves the collapsed notch after the shared paused-content interval.
    /// Presentation only: phase, remaining time and the open session are untouched.
    public private(set) var hidesPausedTimer = false
    /// One pause instant for opening-page arbitration. Restored paused timers do not restart
    /// the grace; a monotonic instant is meaningful only within this process lifetime.
    public private(set) var pauseInstant: ContinuousClock.Instant?

    @ObservationIgnored public weak var focusControl: (any FocusSessionFocusControlling)?
    @ObservationIgnored private let store: any PomodoroPersisting
    @ObservationIgnored private let notifications: NotificationCoordinator
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let soundPlayer: any PomodoroSoundPlaying
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let currentDate: () -> Date
    @ObservationIgnored private let monotonicNow: () -> ContinuousClock.Instant
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var focusSessionActive = false
    @ObservationIgnored private var pauseHideTask: Task<Void, Never>?
    /// One identity for the timer activity, kept across pause hiding and resume.
    @ObservationIgnored private let activityID = UUID()

    static let activityKey = "pomodoro"
    static let resultKey = "pomodoro.result"
    /// Completions older than this (caught up after sleep or relaunch) update history silently.
    static let staleCompletion: TimeInterval = 120

    private enum Keys {
        static let configuration = "notchium.pomodoro.configuration.v1"
        static let collapsed = "notchium.pomodoro.collapsed.v1"
        static let sound = "notchium.pomodoro.sound.v1"
        static let selectedSound = "notchium.pomodoro.selectedSound.v1"
    }

    public init(store: any PomodoroPersisting, notifications: NotificationCoordinator, clock: any AppClock,
                preferences: UserDefaults = .standard, calendar: Calendar = .current,
                now: @escaping () -> Date = Date.init,
                monotonicNow: @escaping () -> ContinuousClock.Instant = { ContinuousClock().now },
                soundPlayer: any PomodoroSoundPlaying = SystemPomodoroSoundPlayer()) {
        self.store = store
        self.notifications = notifications
        self.clock = clock
        self.preferences = preferences
        self.soundPlayer = soundPlayer
        self.calendar = calendar
        currentDate = now
        self.monotonicNow = monotonicNow
        let archive = store.load()
        state = archive.state
        records = archive.records
        configuration = preferences.data(forKey: Keys.configuration)
            .flatMap { try? JSONDecoder().decode(PomodoroConfiguration.self, from: $0) } ?? .standard
        collapsedPreference = preferences.string(forKey: Keys.collapsed).flatMap(CollapsedTimerPreference.init) ?? .timer
        completionSound = preferences.string(forKey: Keys.selectedSound).flatMap(PomodoroSound.init(rawValue:))
            ?? (preferences.bool(forKey: Keys.sound) ? .glass : .none)
        // Paused before relaunch: long past the grace period.
        if case .paused = state.run { hidesPausedTimer = true }
    }

    /// Restores after relaunch (catching up any deadline that passed while quit) and follows wake.
    public func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        refresh()
        publishActivity()
    }

    public func stop() {
        deadlineTask?.cancel(); deadlineTask = nil
        pauseHideTask?.cancel(); pauseHideTask = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        notifications.dismiss(coalescingKey: Self.activityKey)
        dismissCompletion()
        soundPlayer.stop()
        store.flush()
    }

    isolated deinit { stop() }

    // MARK: Controls

    public func startTimer() { apply { PomodoroEngine.start(&$0, configuration: configuration, at: $1); return [] } }
    public func pause() { apply { PomodoroEngine.pause(&$0, at: $1); return [] } }
    public func resume() { apply { PomodoroEngine.resume(&$0, at: $1); return [] } }
    public func skip() {
        guard state.isActive || state.phase.isBreak else { return }
        let phaseToSkip = state.phase
        apply { next, now in
            // Catch-up may have already completed the phase the user clicked Skip on.
            let events = next.phase == phaseToSkip
                ? PomodoroEngine.skip(&next, configuration: configuration, at: now) : []
            PomodoroEngine.start(&next, configuration: configuration, at: now)
            return events
        }
    }
    public func end() {
        dismissCompletion()
        apply { PomodoroEngine.end(&$0, at: $1) }
    }

    public func previewCompletionSound() {
        guard completionSound != .none else { return }
        soundPlayer.play(completionSound)
    }

    public func dismissCompletion() { notifications.dismiss(coalescingKey: Self.resultKey) }

    func perform(_ control: PomodoroControl) {
        guard state.controls.contains(control) else { return }
        switch control {
        case .addFiveMinutes:
            apply { state, _ in
                PomodoroEngine.addFiveMinutes(&state, configuration: configuration)
                return []
            }
        case .startFocus:
            apply {
                if $0.phase.isBreak { _ = PomodoroEngine.skip(&$0, configuration: configuration, at: $1) }
                PomodoroEngine.start(&$0, configuration: configuration, at: $1)
                return []
            }
        case .startBreak: startTimer()
        case .pause: pause()
        case .resume: resume()
        case .skip, .skipBreak: skip()
        case .takeBreak:
            apply { PomodoroEngine.skip(&$0, configuration: configuration, at: $1) }
        case .endFocus: end()
        }
    }

    /// The single primary control: Start, Pause or Resume.
    public func primaryAction() {
        switch state.run {
        case .ready: startTimer()
        case .running: pause()
        case .paused: resume()
        }
    }

    /// Completes any deadline that has passed. Safe to call at any time.
    public func refresh(at date: Date? = nil) {
        let now = date ?? currentDate()
        guard case let .running(endsAt) = state.run, endsAt <= now else {
            scheduleDeadline()
            return
        }
        apply(at: now) { PomodoroEngine.advance(&$0, configuration: configuration, to: $1) }
    }

    public func setPageVisible(_ visible: Bool) {
        guard isPageVisible != visible else { return }
        isPageVisible = visible
        if visible { refresh() }
    }

    // MARK: Derived

    public func countdown(at now: Date? = nil) -> NotchCountdown {
        let total = state.phaseDuration > 0 ? state.phaseDuration : configuration.duration(of: state.phase)
        if case let .running(endsAt) = state.run { return .running(total: total, endsAt: endsAt) }
        return .paused(total: total, remaining: PomodoroEngine.remaining(state, configuration: configuration,
                                                                         at: now ?? currentDate()))
    }

    public func statistics(at now: Date? = nil) -> PomodoroStatistics {
        let date = now ?? currentDate()
        return PomodoroStatistics(records: records, openSegments: PomodoroEngine.liveSegments(state, at: date),
                                  now: date, calendar: calendar)
    }

    public var focusNumber: Int { state.focusNumber(of: configuration) }

    var notificationsForTesting: NotificationCoordinator { notifications }

    // MARK: Transitions

    private func apply(at date: Date? = nil,
                       _ transition: (inout PomodoroState, Date) -> [PomodoroEvent]) {
        let now = date ?? currentDate()
        var next = state
        // A deadline that already passed is completed first, so a late click never extends it.
        var events = PomodoroEngine.advance(&next, configuration: configuration, to: now)
        events += transition(&next, now)
        if case .paused = next.run {
            if case .running = state.run { pauseInstant = monotonicNow() }
        } else { pauseInstant = nil }
        if next.phase != state.phase || next.run != state.run { dismissCompletion() }
        state = next
        for event in events {
            switch event {
            case let .focusCompleted(record, _): records.append(record)
            case let .focusInterrupted(record?): records.append(record)
            case .focusInterrupted(nil), .breakCompleted: break
            }
        }
        store.save(PomodoroArchive(state: state, records: records))
        announce(events.last, now: now)
        updatePausedPresentation()
        publishActivity()
        scheduleDeadline()
        updateFocusControl()
    }

    private func scheduleDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard case let .running(endsAt) = state.run else { return }
        let delay = max(0, endsAt.timeIntervalSince(currentDate()))
        deadlineTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: .milliseconds(Int64((delay * 1000).rounded(.up)))) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Running timers are always eligible; a paused one stays briefly, then leaves the collapsed
    /// notch. Resuming makes it eligible again at once, with the same activity identity.
    private func updatePausedPresentation() {
        guard case .paused = state.run else {
            pauseHideTask?.cancel(); pauseHideTask = nil
            hidesPausedTimer = false
            return
        }
        guard !hidesPausedTimer, pauseHideTask == nil else { return }
        pauseHideTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: ActivityPriorityPolicy.pausedPresentationExpiry) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pauseHideTask = nil
            guard case .paused = self.state.run else { return }
            self.hidesPausedTimer = true
            self.publishActivity()
        }
    }

    private func updateFocusControl() {
        let focusing = state.phase == .focus && state.isActive
        guard focusing != focusSessionActive else { return }
        focusSessionActive = focusing
        if focusing { focusControl?.focusSessionBegan() } else { focusControl?.focusSessionEnded() }
    }

    // MARK: Presentation

    /// One persistent activity while the timer runs or is paused; submitted only on changes.
    func publishActivity() {
        guard state.isActive, !hidesPausedTimer else {
            notifications.dismiss(coalescingKey: Self.activityKey)
            return
        }
        let countdown = countdown()
        let symbol = PomodoroStyle.symbol(state.phase)
        notifications.present(NotchNotification(
            id: activityID, kind: collapsedPreference == .timer ? .focusTimer : .focusTimerBesideMusic,
            dismissible: false, coalescingKey: Self.activityKey, action: .pomodoro, presentationStyle: .compact,
            content: .compact(.init(glyph: .symbol(symbol), title: state.phase.title, showsTitle: false,
                                    trailing: .countdown(countdown), tint: countdown.isRunning ? .primary : .muted,
                                    blendsWithMedia: collapsedPreference == .timer)),
            lifetime: .persistent, minimal: .countdown(countdown)))
    }

    private func announce(_ event: PomodoroEvent?, now: Date) {
        // A completion consumed by a start/skip click no longer needs ready-stage controls.
        guard state.run == .ready else { return }
        let title: String, at: Date
        switch event {
        case let .focusCompleted(record, _)?:
            title = "Focus Complete"
            at = record.end
        case let .breakCompleted(phase, time)?:
            title = phase == .longBreak ? "Cycle Complete" : "Break Over"
            at = time
        default: return
        }
        // Caught-up completions (after sleep or relaunch) only update history.
        guard now.timeIntervalSince(at) < Self.staleCompletion else { return }
        notifications.present(NotchNotification(
            kind: .focusTimerComplete, coalescingKey: Self.resultKey, action: .pomodoro,
            presentationStyle: .pomodoroCompletion, content: .pomodoroCompletion(title: title)))
        if completionSound != .none { soundPlayer.play(completionSound) }
    }
}

extension PomodoroModel: NotchPomodoroRendering {
    public var automaticOpenPageState: NotchPomodoroPageState {
        switch state.run {
        case .running: .running
        case .paused:
            pauseInstant.map { .paused(at: $0) } ?? .inactive
        case .ready: .inactive
        }
    }

    public func expandedPomodoro() -> AnyView { AnyView(PomodoroPageView(model: self)) }

    public func completionBanner(title: String, openTimer: @escaping @MainActor () -> Void) -> AnyView {
        AnyView(PomodoroCompletionView(model: self, title: title, openTimer: openTimer))
    }
}
