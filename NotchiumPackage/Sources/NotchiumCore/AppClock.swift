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
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var currentDate: Date
    private let automaticallyAdvances: Bool
    private var requestedSleeps: [Duration] = []
    private var sleepers: [UUID: Sleeper] = [:]
    private var sleepObservers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    public init(now: Date, automaticallyAdvances: Bool = true) {
        currentDate = now
        self.automaticallyAdvances = automaticallyAdvances
    }

    public func now() -> Date { currentDate }

    public func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        requestedSleeps.append(duration)
        if automaticallyAdvances {
            currentDate = currentDate.addingTimeInterval(duration.timeInterval)
            return
        }
        guard duration > .zero else { return }
        let id = UUID()
        let deadline = currentDate.addingTimeInterval(duration.timeInterval)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Cancellation before registration must not leave an orphan sleeper.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    notifySleepObservers()
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    public func advance(by duration: Duration) {
        precondition(duration >= .zero)
        currentDate = currentDate.addingTimeInterval(duration.timeInterval)
        let ready = sleepers.filter { $0.value.deadline <= currentDate }
        for (id, sleeper) in ready {
            sleepers.removeValue(forKey: id)
            sleeper.continuation.resume()
        }
    }

    public func sleepHistory() -> [Duration] { requestedSleeps }
    public func pendingSleepCount() -> Int { sleepers.count }

    /// Synchronizes tests with task registration before advancing fake time.
    public func waitForPendingSleeps(_ count: Int = 1) async {
        if sleepers.count >= count { return }
        await withCheckedContinuation { continuation in
            sleepObservers.append((count, continuation))
        }
    }

    private func notifySleepObservers() {
        let ready = sleepObservers.filter { sleepers.count >= $0.count }
        sleepObservers.removeAll { sleepers.count >= $0.count }
        for observer in ready { observer.continuation.resume() }
    }

    private func cancel(id: UUID) {
        sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
