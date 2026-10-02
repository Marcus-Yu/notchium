import Foundation

public enum PomodoroPhase: String, Codable, Sendable {
    case focus, shortBreak, longBreak

    public var isBreak: Bool { self != .focus }

    public var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Break"
        case .longBreak: "Long Break"
        }
    }
}

/// Defaults are 30 / 5 / 15 with a long break after every fourth Focus session.
public struct PomodoroConfiguration: Codable, Equatable, Sendable {
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    public var sessionsPerCycle: Int

    public init(focusMinutes: Int = 30, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 15,
                sessionsPerCycle: Int = 4) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.sessionsPerCycle = sessionsPerCycle
    }

    public static let standard = PomodoroConfiguration()

    public func duration(of phase: PomodoroPhase) -> TimeInterval {
        let minutes = switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
        return TimeInterval(max(1, minutes) * 60)
    }
}

/// One Focus session as it happened. History, streaks and totals are all derived from these;
/// nothing else counts sessions or time.
public struct FocusSessionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    /// Time actually spent focusing; pauses are gaps between segments.
    public let segments: [DateInterval]
    public let completed: Bool
    /// 1-based position in the cycle (1…4 by default).
    public let cycleIndex: Int

    public var focusedDuration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }
}

/// Persisted timer truth: a phase, how it is running (deadline or frozen remainder), and the
/// open Focus session's segments. The visible time is always derived from `endsAt`.
public struct PomodoroState: Codable, Equatable, Sendable {
    public enum Run: Codable, Equatable, Sendable {
        /// Not counting; `phase` is the one ready to start.
        case ready
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
    }

    public var phase: PomodoroPhase = .focus
    public var run: Run = .ready
    /// Focus sessions already taken in this cycle (completed or skipped), 0…sessionsPerCycle.
    public var cyclePosition = 0
    /// The phase's full length, set by a ready-phase extension or when it starts. Once set,
    /// settings changes never warp it; zero uses the configured duration.
    public var phaseDuration: TimeInterval = 0
    public var session: OpenSession?

    public struct OpenSession: Codable, Equatable, Sendable {
        public let id: UUID
        public let start: Date
        public var segments: [DateInterval] = []
        public var segmentStart: Date?
    }

    public init() {}

    public var isActive: Bool { run != .ready }
    /// 1-based number of the current (or next) Focus session in the cycle.
    public func focusNumber(of configuration: PomodoroConfiguration) -> Int {
        min(cyclePosition + (phase == .focus ? 1 : 0), configuration.sessionsPerCycle).clamped(1)
    }
}

/// What a transition produced, for history and presentation.
public enum PomodoroEvent: Equatable, Sendable {
    case focusCompleted(FocusSessionRecord, next: PomodoroPhase)
    case breakCompleted(PomodoroPhase, at: Date)
    /// An unfinished Focus session that was skipped or ended (dropped when under a minute).
    case focusInterrupted(FocusSessionRecord?)
}

/// Pure transitions. Every function takes the time explicitly, so catch-up after sleep or
/// relaunch is the same code path as a live deadline.
public enum PomodoroEngine {
    /// Interrupted sessions shorter than this are treated as accidental and not recorded.
    public static let minimumRecordedFocus: TimeInterval = 60

    public static func start(_ state: inout PomodoroState, configuration: PomodoroConfiguration, at now: Date) {
        guard state.run == .ready else { return }
        if state.phaseDuration <= 0 { state.phaseDuration = configuration.duration(of: state.phase) }
        state.run = .running(endsAt: now.addingTimeInterval(state.phaseDuration))
        if state.phase == .focus {
            state.session = .init(id: UUID(), start: now, segmentStart: now)
        }
    }

    /// Extends only an upcoming phase, without starting it or changing the saved defaults.
    public static func addFiveMinutes(_ state: inout PomodoroState, configuration: PomodoroConfiguration) {
        guard state.run == .ready else { return }
        let duration = state.phaseDuration > 0 ? state.phaseDuration : configuration.duration(of: state.phase)
        state.phaseDuration = duration + 5 * 60
    }

    public static func pause(_ state: inout PomodoroState, at now: Date) {
        guard case let .running(endsAt) = state.run else { return }
        state.run = .paused(remaining: max(0, endsAt.timeIntervalSince(now)))
        closeSegment(&state, at: now)
    }

    public static func resume(_ state: inout PomodoroState, at now: Date) {
        guard case let .paused(remaining) = state.run else { return }
        state.run = .running(endsAt: now.addingTimeInterval(remaining))
        if state.phase == .focus { state.session?.segmentStart = now }
    }

    /// Completes a deadline that has passed by `now`. Every next phase stays ready until
    /// explicitly started, including when catching up after sleep or relaunch.
    public static func advance(_ state: inout PomodoroState, configuration: PomodoroConfiguration,
                               to now: Date) -> [PomodoroEvent] {
        var events: [PomodoroEvent] = []
        while case let .running(endsAt) = state.run, endsAt <= now {
            if state.phase == .focus {
                closeSegment(&state, at: endsAt)
                let record = closeSession(&state, at: endsAt, completed: true)
                state.cyclePosition += 1
                let next: PomodoroPhase = state.cyclePosition >= configuration.sessionsPerCycle ? .longBreak : .shortBreak
                state.phase = next
                state.phaseDuration = 0
                state.run = .ready
                if let record { events.append(.focusCompleted(record, next: next)) }
            } else {
                let finished = state.phase
                finishBreak(&state)
                events.append(.breakCompleted(finished, at: endsAt))
            }
        }
        return events
    }

    /// Focus → its break; a break → the next Focus. The next phase is always ready.
    public static func skip(_ state: inout PomodoroState, configuration: PomodoroConfiguration,
                            at now: Date) -> [PomodoroEvent] {
        if state.phase == .focus {
            guard state.run != .ready else { return [] }
            closeSegment(&state, at: now)
            let record = closeSession(&state, at: now, completed: false)
            state.cyclePosition += 1
            let next: PomodoroPhase = state.cyclePosition >= configuration.sessionsPerCycle ? .longBreak : .shortBreak
            state.phase = next
            state.phaseDuration = 0
            state.run = .ready
            return [.focusInterrupted(record)]
        }
        finishBreak(&state)
        return []
    }

    /// Ends the cycle: an open Focus session is recorded as interrupted, then everything resets.
    public static func end(_ state: inout PomodoroState, at now: Date) -> [PomodoroEvent] {
        var events: [PomodoroEvent] = []
        if state.phase == .focus, state.session != nil {
            closeSegment(&state, at: now)
            events.append(.focusInterrupted(closeSession(&state, at: now, completed: false)))
        }
        state = PomodoroState()
        return events
    }

    /// Remaining time of the current phase.
    public static func remaining(_ state: PomodoroState, configuration: PomodoroConfiguration, at now: Date) -> TimeInterval {
        switch state.run {
        case .ready: state.phaseDuration > 0 ? state.phaseDuration : configuration.duration(of: state.phase)
        case let .running(endsAt): max(0, endsAt.timeIntervalSince(now))
        case let .paused(remaining): remaining
        }
    }

    /// Focus time of the open session, including a running segment up to `now`.
    public static func liveSegments(_ state: PomodoroState, at now: Date) -> [DateInterval] {
        guard let session = state.session else { return [] }
        var segments = session.segments
        if let start = session.segmentStart, now > start { segments.append(DateInterval(start: start, end: now)) }
        return segments
    }

    private static func finishBreak(_ state: inout PomodoroState) {
        if state.phase == .longBreak { state.cyclePosition = 0 }
        state.phase = .focus
        state.run = .ready
        state.phaseDuration = 0
    }

    private static func closeSegment(_ state: inout PomodoroState, at time: Date) {
        guard let start = state.session?.segmentStart else { return }
        if time > start { state.session?.segments.append(DateInterval(start: start, end: time)) }
        state.session?.segmentStart = nil
    }

    private static func closeSession(_ state: inout PomodoroState, at time: Date, completed: Bool) -> FocusSessionRecord? {
        guard let session = state.session else { return nil }
        state.session = nil
        let record = FocusSessionRecord(id: session.id, start: session.start, end: time, segments: session.segments,
                                        completed: completed, cycleIndex: state.cyclePosition + 1)
        if !completed, record.focusedDuration < minimumRecordedFocus { return nil }
        return record
    }
}

/// Everything shown about history, derived on demand from the records in the local calendar.
public struct PomodoroStatistics: Equatable, Sendable {
    public struct Day: Equatable, Identifiable, Sendable {
        public let date: Date
        public let focus: TimeInterval
        public let sessions: Int
        public var id: Date { date }
    }

    public let todayFocus: TimeInterval
    public let todaySessions: Int
    /// Consecutive days with at least one completed Focus session, ending today, or yesterday
    /// while today has none yet.
    public let streak: Int
    /// The previous 30 calendar days, oldest first, ending today.
    public let days: [Day]
    public let totalSessions: Int
    public let totalFocus: TimeInterval

    public init(records: [FocusSessionRecord], openSegments: [DateInterval] = [], now: Date,
                calendar: Calendar = .current, dayCount: Int = 30) {
        let today = calendar.startOfDay(for: now)
        let allSegments = records.flatMap(\.segments) + openSegments
        let completed = records.filter(\.completed)

        func focus(on day: Date) -> TimeInterval {
            guard let interval = calendar.dateInterval(of: .day, for: day) else { return 0 }
            return allSegments.reduce(0) { total, segment in
                total + (segment.intersection(with: interval)?.duration ?? 0)
            }
        }

        var sessionsPerDay: [Date: Int] = [:]
        for record in completed { sessionsPerDay[calendar.startOfDay(for: record.end), default: 0] += 1 }

        todayFocus = focus(on: today)
        todaySessions = sessionsPerDay[today, default: 0]
        days = (0..<dayCount).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { date in
                Day(date: date, focus: focus(on: date), sessions: sessionsPerDay[date, default: 0])
            }
        }

        var streak = 0
        var cursor = sessionsPerDay[today] != nil ? today : calendar.date(byAdding: .day, value: -1, to: today)
        while let day = cursor, sessionsPerDay[day] != nil {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }
        self.streak = streak
        totalSessions = completed.count
        totalFocus = allSegments.reduce(0) { $0 + $1.duration }
    }

    /// "1h 32m", "45m", "0m".
    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }
}

private extension Int {
    func clamped(_ lower: Int) -> Int { Swift.max(lower, self) }
}
