import Combine
import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation

/// Schedules reminders from Calendar value snapshots. EventKit remains in CalendarService.
@MainActor
@Observable
public final class CalendarReminderCoordinator {
    public struct Reminder: Equatable, Sendable {
        public let event: CalendarEventSummary
        public let label: String
        public let isImminent: Bool
        public let isNow: Bool
    }

    public private(set) var current: Reminder?
    @ObservationIgnored private let activities: ActivityCoordinator
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var events: [CalendarEventSummary] = []
    @ObservationIgnored private var shown: [UUID: Set<Int>] = [:]
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var activityObservation: AnyCancellable?
    @ObservationIgnored private var activeID: UUID?
    @ObservationIgnored private var remaining: TimeInterval = 10
    @ObservationIgnored private var timerStarted: Date?
    @ObservationIgnored private var hovering = false
    @ObservationIgnored private var generation = 0

    public static let thresholds: [Int] = [3600, 1800, 300]
    public static let displayDuration: TimeInterval = 10
    public static let priority = 25

    public init(activities: ActivityCoordinator, clock: any AppClock = ContinuousAppClock()) {
        self.activities = activities
        self.clock = clock
        activityObservation = activities.$activeActivity.sink { [weak self] activity in
            Task { @MainActor [weak self] in self?.activityChanged(to: activity) }
        }
    }

    public func update(events: [CalendarEventSummary]) async {
        self.events = events.filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
        boundaryTask?.cancel()
        let now = await clock.now()
        if let current, !self.events.contains(where: { $0.id == current.event.id && $0.endDate > now }) {
            dismiss()
        } else if let current, current.event.startDate > now {
            // A refresh after sleep must never leave a stale pre-sleep countdown visible.
            let label = Self.label(for: current.event, at: now)
            if label != current.label {
                self.current = Reminder(event: current.event, label: label,
                    isImminent: current.event.startDate.timeIntervalSince(now) <= 300,
                    isNow: false)
            }
        }
        evaluate(at: now)
        scheduleNextBoundary(after: now)
    }

    public func dismiss() {
        dismissTask?.cancel(); dismissTask = nil
        timerStarted = nil
        hovering = false
        current = nil
        if let activeID { activities.dismiss(id: activeID) }
        activeID = nil
    }

    public func stop() {
        boundaryTask?.cancel(); boundaryTask = nil
        dismiss()
        events = []
        shown = [:]
    }

    public func setHovered(_ hovered: Bool) {
        guard hovering != hovered else { return }
        hovering = hovered
        if hovered {
            pauseDismissTimer()
        } else if activities.activeActivity?.id == activeID {
            startDismissTimer()
        }
    }

    private func evaluate(at now: Date) {
        var due: [(CalendarEventSummary, Int)] = []
        for event in events where event.endDate > now {
            let seconds = event.startDate.timeIntervalSince(now)
            var seen = shown[event.id, default: []]
            for threshold in Self.thresholds where seconds <= Double(threshold) {
                if seen.insert(threshold).inserted && seconds > 0 {
                    due.append((event, threshold))
                }
            }
            if seconds <= 0, event.meetingURL != nil, seen.insert(0).inserted {
                due.append((event, 0))
            }
            shown[event.id] = seen
        }
        guard let selected = due.min(by: { $0.0.startDate < $1.0.startDate }) else { return }
        let event = selected.0
        let seconds = event.startDate.timeIntervalSince(now)
        let label = Self.label(for: event, at: now)
        // Do not queue a stale reminder behind a higher-priority system activity.
        guard activities.activeActivity?.priority ?? 0 <= Self.priority else { return }
        dismiss()
        let id = UUID()
        activeID = id
        remaining = Self.displayDuration
        current = Reminder(event: event, label: label,
                           isImminent: seconds <= 300, isNow: seconds <= 0)
        activities.present(.init(id: id, kind: .calendar, title: event.title,
                                 subtitle: label, priority: Self.priority, duration: nil))
        startDismissTimer()
    }

    private static func label(for event: CalendarEventSummary, at now: Date) -> String {
        let seconds = event.startDate.timeIntervalSince(now)
        if seconds <= 0 { return "Now" }
        if seconds >= 3590 { return "in 1 hr" }
        return "\(max(1, Int(ceil(seconds / 60)))) min"
    }

    private func scheduleNextBoundary(after now: Date) {
        let dates = events.flatMap { event in
            Self.thresholds.map { event.startDate.addingTimeInterval(-Double($0)) }
            + (event.meetingURL == nil ? [] : [event.startDate])
        }
        guard let next = dates.filter({ $0 > now }).min() else { return }
        boundaryTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: .seconds(next.timeIntervalSince(now))) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            let currentTime = await clock.now()
            self.evaluate(at: currentTime)
            self.scheduleNextBoundary(after: currentTime)
        }
    }

    private func activityChanged(to activity: NotchActivity?) {
        guard activity?.id == activities.activeActivity?.id else { return }
        guard activeID != nil else { return }
        if activity?.id == activeID {
            if !hovering && dismissTask == nil { startDismissTimer() }
        } else {
            pauseDismissTimer()
        }
    }

    private func pauseDismissTimer() {
        dismissTask?.cancel(); dismissTask = nil
        guard let timerStarted else { return }
        remaining = max(0, remaining - Date.now.timeIntervalSince(timerStarted))
        self.timerStarted = nil
    }

    private func startDismissTimer() {
        guard current != nil, !hovering, dismissTask == nil else { return }
        generation &+= 1
        let token = generation
        timerStarted = .now
        dismissTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: .seconds(max(0.01, self?.remaining ?? 0.01))) }
            catch { return }
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.dismiss()
        }
    }
}
