import Foundation

/// Explicit wall time and monotonic elapsed time since an injected process-run origin.
/// AppClock.now() supplies only the former. No clock is consulted here.
public struct ProactiveTime: Equatable, Sendable {
    public let wallDate: Date
    public let elapsed: Duration
    public let runID: UUID

    public init(wallDate: Date, elapsed: Duration, runID: UUID) {
        self.wallDate = wallDate
        self.elapsed = elapsed
        self.runID = runID
    }

    public var isValid: Bool { wallDate.timeIntervalSinceReferenceDate.isFinite && elapsed >= .zero }

    public func advanced(by duration: Duration) -> Self {
        Self(wallDate: wallDate.addingTimeInterval(duration.timeInterval),
             elapsed: elapsed + duration, runID: runID)
    }
}

/// Wall bounds can be retained across runs; elapsed bounds apply only to startedAt.runID.
public struct SuggestionCooldown: Equatable, Sendable {
    public let startedAt: ProactiveTime
    public let duration: Duration
    public var wallUntil: Date { startedAt.wallDate.addingTimeInterval(duration.timeInterval) }

    public init(startedAt: ProactiveTime, duration: Duration) {
        self.startedAt = startedAt
        self.duration = max(.zero, duration)
    }

    public func remaining(at time: ProactiveTime) -> Duration {
        if time.runID == startedAt.runID {
            // A malformed backwards elapsed input must not clear silence.
            return max(.zero, duration - max(.zero, time.elapsed - startedAt.elapsed))
        }
        return .seconds(max(0, wallUntil.timeIntervalSince(time.wallDate)))
    }
}
