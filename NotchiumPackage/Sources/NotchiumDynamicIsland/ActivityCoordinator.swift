import Combine
import Foundation
import NotchiumCore

@MainActor
public final class ActivityCoordinator: ObservableObject {
    @Published public private(set) var activeActivity: NotchActivity?
    @Published public private(set) var queueCount = 0
    private var queuedActivities: [NotchActivity] = []
    private let clock: any AppClock
    private var timeoutTask: Task<Void, Never>?
    private var timeoutGeneration = 0

    public init(clock: any AppClock) {
        self.clock = clock
    }

    deinit { timeoutTask?.cancel() }

    public func present(_ activity: NotchActivity) {
        // An identity represents one event; repeated delivery must not duplicate it.
        guard activeActivity?.id != activity.id,
              !queuedActivities.contains(where: { $0.id == activity.id }) else { return }
        guard let activeActivity else {
            activate(activity)
            return
        }
        if activity.priority > activeActivity.priority {
            enqueue(activeActivity)
            activate(activity)
        } else {
            enqueue(activity)
        }
    }

    public func dismissActive() {
        // Stable sort preserves the oldest queue entry for equal priorities.
        let next = queuedActivities.indices.reduce(nil as Int?) { best, index in
            guard let best else { return index }
            return queuedActivities[index].priority > queuedActivities[best].priority ? index : best
        }
        let activity = next.map { queuedActivities.remove(at: $0) }
        queueCount = queuedActivities.count
        activate(activity)
    }

    public func dismiss(id: UUID) {
        if activeActivity?.id == id {
            dismissActive()
        } else {
            queuedActivities.removeAll { $0.id == id }
            queueCount = queuedActivities.count
        }
    }

    public func dismiss(kind: NotchActivityKind) {
        queuedActivities.removeAll { $0.kind == kind }
        queueCount = queuedActivities.count
        if activeActivity?.kind == kind { dismissActive() }
    }

    public func clearQueue() {
        queuedActivities.removeAll()
        queueCount = 0
    }

    public func clearAll() {
        clearQueue()
        activate(nil)
    }

    private func enqueue(_ activity: NotchActivity) {
        queuedActivities.append(activity)
        queueCount = queuedActivities.count
    }

    private func activate(_ activity: NotchActivity?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        timeoutGeneration &+= 1
        activeActivity = activity
        guard let activity, let duration = activity.duration else { return }
        let generation = timeoutGeneration
        // Each activation receives its full duration, including after interruption.
        timeoutTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: duration)
            } catch { return }
            guard !Task.isCancelled, let self,
                  self.timeoutGeneration == generation,
                  self.activeActivity?.id == activity.id else { return }
            self.dismissActive()
        }
    }
}
