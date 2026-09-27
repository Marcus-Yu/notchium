import Foundation
import NotchiumCore
import Observation

/// A subordinate, single-slot notification policy. ActivityCoordinator remains the
/// global arbiter. Notification activities have no second activity expiry timer.
@MainActor
@Observable
public final class NotificationCoordinator {
    public private(set) var active: NotchNotification?
    public private(set) var isHovered = false
    public private(set) var interactingID: UUID?
    @ObservationIgnored weak var activities: ActivityCoordinator?
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var remaining: TimeInterval = 0

    init(clock: any AppClock) { self.clock = clock }
    deinit { timeoutTask?.cancel() }

    /// Equal priority replaces; lower priority is discarded, never replayed later.
    @discardableResult
    public func present(_ notification: NotchNotification) -> Bool {
        guard let activities else { return false }
        if let current = activities.activeTransient, current.priority > notification.priority { return false }
        var incoming = notification
        if let active, active.coalescingKey == incoming.coalescingKey {
            incoming.id = active.id
        }
        let previousID = active?.id
        if incoming.id != previousID { interactingID = nil }
        active = incoming
        remaining = incoming.duration.timeInterval
        deadline = nil
        activities.presentNotification(incoming.activity, replacing: previousID)
        scheduleTimeout()
        return true
    }

    public func dismiss(id: UUID? = nil) {
        guard let active, id == nil || id == active.id else { return }
        clear()
        activities?.dismiss(id: active.id)
    }

    public func dismissByUser(id: UUID? = nil) {
        guard active?.dismissible == true, id == nil || id == active?.id else { return }
        dismiss()
    }

    public func setInteracting(_ interacting: Bool, id: UUID) {
        guard active?.id == id else { return }
        let wasRetained = isHovered || interactingID != nil
        interactingID = interacting ? id : nil
        retentionChanged(wasRetained: wasRetained)
    }

    public func setHovered(_ hovered: Bool) {
        guard active != nil, isHovered != hovered else { return }
        let wasRetained = isHovered || interactingID != nil
        isHovered = hovered
        retentionChanged(wasRetained: wasRetained)
    }

    private func retentionChanged(wasRetained: Bool) {
        let retained = isHovered || interactingID != nil
        guard retained != wasRetained else { return }
        generation &+= 1
        let token = generation
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, clock] in
            let now = await clock.now()
            guard let self, self.generation == token else { return }
            if retained {
                if let deadline = self.deadline {
                    self.remaining = max(0, deadline.timeIntervalSince(now))
                    self.deadline = nil
                }
            }
            self.scheduleTimeout()
        }
    }

    /// Called synchronously by the global arbiter; preempted feedback is not queued.
    func activityChanged(_ activity: NotchActivity?) {
        guard let active, activity?.id != active.id else { return }
        clear()
    }

    private func clear() {
        active = nil
        isHovered = false
        interactingID = nil
        deadline = nil
        remaining = 0
        generation &+= 1
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func scheduleTimeout() {
        generation &+= 1
        let token = generation
        timeoutTask?.cancel()
        timeoutTask = nil
        guard active != nil, !isHovered, interactingID == nil else { return }
        timeoutTask = Task { [weak self, clock] in
            let now = await clock.now()
            guard let self, self.generation == token else { return }
            let deadline = self.deadline ?? now.addingTimeInterval(self.remaining)
            self.deadline = deadline
            let delay = max(0, deadline.timeIntervalSince(now))
            do { try await clock.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled, self.generation == token else { return }
            self.dismiss()
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
