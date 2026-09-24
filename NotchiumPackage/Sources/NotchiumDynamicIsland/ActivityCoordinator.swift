import Combine
import Foundation
import NotchiumCore

/// Arbitrates one persistent baseline and a bounded set of transient activity families.
/// Features submit semantic activities; display-specific geometry remains in the shell layer.
@MainActor
public final class ActivityCoordinator: ObservableObject {
    @Published public private(set) var persistentActivity: NotchActivity?
    @Published public private(set) var activeTransient: NotchActivity?
    @Published public private(set) var queueCount = 0
    @Published public private(set) var presentationMode: NotchPresentationMode = .none

    public var activeActivity: NotchActivity? { activeTransient ?? persistentActivity }

    public func contains(id: UUID) -> Bool {
        persistentActivity?.id == id
            || activeEntry?.activity.id == id
            || pendingByFamily.values.contains(where: { $0.activity.id == id })
    }

    private struct Entry {
        var activity: NotchActivity
        var expiresAt: Date?
        var remaining: Duration?
    }

    private var activeEntry: Entry?
    private var pendingByFamily: [NotchActivityFamily: Entry] = [:]
    private let clock: any AppClock
    private var timeoutTask: Task<Void, Never>?
    private var timeoutGeneration = 0
    private var hoverGeneration = 0
    private var activeIsHovered = false
    private var lastKnownNow: Date?

    public init(clock: any AppClock) {
        self.clock = clock
    }

    deinit { timeoutTask?.cancel() }

    public func present(_ activity: NotchActivity) {
        if activity.lifetime == .persistent {
            persistentActivity = activity
            publishState()
            return
        }

        var incoming = Entry(activity: activity, expiresAt: nil, remaining: activity.duration)

        if let activeEntry, activeEntry.activity.family == activity.family {
            incoming.activity = coalesced(existing: activeEntry.activity, incoming: activity)
            incoming.remaining = incoming.activity.duration
            self.activeEntry = incoming
            publishState()
            scheduleTimeout()
            return
        }

        if let pending = pendingByFamily[activity.family] {
            incoming.activity = coalesced(existing: pending.activity, incoming: activity)
            incoming.remaining = incoming.activity.duration
        }

        guard let current = activeEntry else {
            activate(incoming)
            return
        }

        if incoming.activity.priority > current.activity.priority {
            pendingByFamily[current.activity.family] = current
            activate(incoming)
        } else {
            pendingByFamily[activity.family] = incoming
            publishState()
            scheduleTimeout()
        }
    }

    public func dismissActive() {
        activeEntry = nil
        activeIsHovered = false
        promoteNext(at: lastKnownNow)
    }

    public func dismiss(id: UUID) {
        if persistentActivity?.id == id { persistentActivity = nil }
        pendingByFamily = pendingByFamily.filter { $0.value.activity.id != id }
        if activeEntry?.activity.id == id {
            activeEntry = nil
            activeIsHovered = false
            promoteNext(at: lastKnownNow)
        } else {
            publishState()
            scheduleTimeout()
        }
    }

    public func dismiss(kind: NotchActivityKind) {
        if persistentActivity?.kind == kind { persistentActivity = nil }
        pendingByFamily = pendingByFamily.filter { $0.value.activity.kind != kind }
        if activeEntry?.activity.kind == kind {
            activeEntry = nil
            activeIsHovered = false
            promoteNext(at: lastKnownNow)
        } else {
            publishState()
            scheduleTimeout()
        }
    }

    public func setHovered(_ hovered: Bool) {
        guard activeEntry != nil, activeIsHovered != hovered else { return }
        activeIsHovered = hovered
        hoverGeneration &+= 1
        let generation = hoverGeneration
        timeoutTask?.cancel()
        timeoutTask = nil

        Task { @concurrent [weak self, clock] in
            let now = await clock.now()
            await self?.applyHoverState(hovered, at: now, generation: generation)
        }
    }

    public func clearQueue() {
        pendingByFamily.removeAll()
        publishState()
        scheduleTimeout()
    }

    public func clearAll() {
        pendingByFamily.removeAll()
        activeEntry = nil
        persistentActivity = nil
        activeIsHovered = false
        publishState()
        scheduleTimeout()
    }

    private func coalesced(existing: NotchActivity, incoming: NotchActivity) -> NotchActivity {
        guard incoming.family == .audio else { return incoming }
        return NotchActivity(
            id: incoming.id,
            kind: incoming.kind,
            title: incoming.title,
            subtitle: incoming.subtitle,
            priority: max(existing.priority, incoming.priority),
            presentationStyle: incoming.presentationStyle,
            lifetime: incoming.lifetime,
            isDismissible: incoming.isDismissible,
            destination: incoming.destination,
            timestamp: incoming.timestamp,
            duration: incoming.duration,
            payload: incoming.payload
        )
    }

    private func activate(_ entry: Entry) {
        activeEntry = entry
        activeIsHovered = false
        publishState()
        scheduleTimeout()
    }

    private func promoteNext(at now: Date?) {
        if let now { removeExpiredPending(at: now) }
        let nextFamily = pendingByFamily.keys.min { lhs, rhs in
            guard let left = pendingByFamily[lhs]?.activity,
                  let right = pendingByFamily[rhs]?.activity else { return false }
            if left.priority != right.priority { return left.priority > right.priority }
            return left.timestamp < right.timestamp
        }
        activeEntry = nextFamily.flatMap { pendingByFamily.removeValue(forKey: $0) }
        publishState()
        scheduleTimeout()
    }

    private func publishState() {
        activeTransient = activeEntry?.activity
        queueCount = pendingByFamily.count
        presentationMode = Self.presentationMode(
            persistent: persistentActivity,
            transient: activeEntry?.activity
        )
    }

    private static func presentationMode(
        persistent: NotchActivity?,
        transient: NotchActivity?
    ) -> NotchPresentationMode {
        guard let transient else {
            return persistent?.presentationStyle == .mediaSides ? .mediaSides : .none
        }
        switch transient.presentationStyle {
        case .none: return persistent?.presentationStyle == .mediaSides ? .mediaSides : .none
        case .mediaSides: return .mediaSides
        case .downwardBanner:
            return transient.family == .calendar && persistent?.presentationStyle == .mediaSides
                ? .combined
                : .downwardBanner
        case .compactHUD: return .compactHUD
        }
    }

    private func applyHoverState(_ hovered: Bool, at now: Date, generation: Int) {
        guard generation == hoverGeneration, activeIsHovered == hovered,
              var activeEntry else { return }
        lastKnownNow = now
        if hovered {
            if let expiresAt = activeEntry.expiresAt {
                activeEntry.remaining = .seconds(max(0, expiresAt.timeIntervalSince(now)))
                activeEntry.expiresAt = nil
            }
        } else if let remaining = activeEntry.remaining {
            activeEntry.expiresAt = now.addingTimeInterval(remaining.timeInterval)
        }
        self.activeEntry = activeEntry
        scheduleTimeout()
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
        timeoutGeneration &+= 1
        let generation = timeoutGeneration
        guard activeEntry?.remaining != nil
                || pendingByFamily.values.contains(where: { $0.remaining != nil }) else { return }

        timeoutTask = Task { @concurrent [weak self, clock] in
            let now = await clock.now()
            guard let delay = await self?.prepareTimeout(at: now, generation: generation) else { return }
            do { try await clock.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            let firedAt = await clock.now()
            await self?.expireActivities(at: firedAt, generation: generation)
        }
    }

    private func prepareTimeout(at now: Date, generation: Int) -> Duration? {
        guard generation == timeoutGeneration else { return nil }
        lastKnownNow = now

        if var activeEntry, activeEntry.remaining != nil,
           activeEntry.expiresAt == nil, !activeIsHovered {
            activeEntry.expiresAt = now.addingTimeInterval(activeEntry.remaining?.timeInterval ?? 0)
            self.activeEntry = activeEntry
        }
        for family in pendingByFamily.keys {
            guard var entry = pendingByFamily[family], entry.remaining != nil,
                  entry.expiresAt == nil else { continue }
            entry.expiresAt = now.addingTimeInterval(entry.remaining?.timeInterval ?? 0)
            pendingByFamily[family] = entry
        }

        let activeDeadline = activeIsHovered ? nil : activeEntry?.expiresAt
        let nextDeadline = ([activeDeadline] + pendingByFamily.values.map(\.expiresAt))
            .compactMap { $0 }
            .min()
        guard let nextDeadline else { return nil }
        return .seconds(max(0, nextDeadline.timeIntervalSince(now)))
    }

    private func expireActivities(at now: Date, generation: Int) {
        guard generation == timeoutGeneration else { return }
        lastKnownNow = now
        removeExpiredPending(at: now)
        if !activeIsHovered, let expiresAt = activeEntry?.expiresAt, expiresAt <= now {
            activeEntry = nil
            promoteNext(at: now)
        } else {
            publishState()
            scheduleTimeout()
        }
    }

    private func removeExpiredPending(at now: Date) {
        pendingByFamily = pendingByFamily.filter { _, entry in
            guard let expiresAt = entry.expiresAt else { return true }
            return expiresAt > now
        }
    }
}

private extension NotchActivity {
    var family: NotchActivityFamily { kind.family }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
