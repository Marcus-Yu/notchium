import Foundation
import Observation

/// One monotonic press lifetime owns progress, the deadline, and mouse-up consumption.
struct CaffeinePressState {
    static let duration: Duration = .milliseconds(750)
    private(set) var startedAt: ContinuousClock.Instant?
    private(set) var completed = false

    mutating func begin(at instant: ContinuousClock.Instant) {
        startedAt = instant
        completed = false
    }

    func progress(at instant: ContinuousClock.Instant) -> Double {
        guard let startedAt else { return 0 }
        return min(1, max(0, startedAt.duration(to: instant) / Self.duration))
    }

    mutating func complete(at instant: ContinuousClock.Instant) -> Bool {
        guard let startedAt, !completed,
              startedAt.duration(to: instant) >= Self.duration else { return false }
        completed = true
        return true
    }

    mutating func end() -> Bool {
        let click = startedAt != nil && !completed
        startedAt = nil
        return click
    }

    mutating func cancel() { startedAt = nil }
}

@MainActor
@Observable
public final class CaffeinePressInteraction {
    public private(set) var isPressed = false
    public private(set) var progress = 0.0
    public private(set) var completionCount = 0
    @ObservationIgnored private var state = CaffeinePressState()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var holdAction: (() -> Void)?
    @ObservationIgnored private var clickAction: (() -> Void)?

    public init() {}
    deinit { task?.cancel() }

    func begin(allowsHold: Bool, click: @escaping () -> Void, hold: @escaping () -> Void,
               at start: ContinuousClock.Instant = .now) {
        guard state.startedAt == nil else { return }
        state.begin(at: start)
        isPressed = true
        clickAction = click
        holdAction = allowsHold ? hold : nil
        guard allowsHold else { return }
        task = Task { @MainActor [weak self] in
            let deadline = start + CaffeinePressState.duration
            while !Task.isCancelled {
                let now = ContinuousClock.now
                self?.advance(to: now)
                guard now < deadline else { return }
                do { try await ContinuousClock().sleep(until: min(now + .milliseconds(16), deadline)) }
                catch { return }
            }
        }
    }

    func advance(to instant: ContinuousClock.Instant) {
        guard let holdAction else { return }
        progress = state.progress(at: instant)
        if state.complete(at: instant) {
            completionCount &+= 1
            holdAction()
        }
    }

    func end(at instant: ContinuousClock.Instant = .now) {
        // Mouse-up can arrive before the scheduled deadline callback on a busy main actor.
        advance(to: instant)
        let click = state.end() ? clickAction : nil
        cancel()
        click?()
    }

    public func cancel() {
        state.cancel()
        isPressed = false
        task?.cancel()
        task = nil
        holdAction = nil
        clickAction = nil
        progress = 0
    }
}
