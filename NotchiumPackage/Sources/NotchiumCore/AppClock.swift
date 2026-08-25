import Foundation

public protocol AppClock: Sendable {
    func now() async -> Date
    func sleep(for duration: Duration) async throws
}

public struct ContinuousAppClock: AppClock {
    public init() {}

    public func now() async -> Date {
        Date()
    }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

public actor TestAppClock: AppClock {
    private var currentDate: Date
    private var requestedSleeps: [Duration] = []

    public init(now: Date) {
        currentDate = now
    }

    public func now() -> Date {
        currentDate
    }

    public func sleep(for duration: Duration) throws {
        try Task.checkCancellation()
        requestedSleeps.append(duration)
        currentDate = currentDate.addingTimeInterval(duration.timeInterval)
    }

    public func advance(by duration: Duration) {
        currentDate = currentDate.addingTimeInterval(duration.timeInterval)
    }

    public func sleepHistory() -> [Duration] {
        requestedSleeps
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
