import Combine
import Foundation
import NotchiumCore

/// Owns presentation policy for every live activity: identity/coalescing, arbitration,
/// primary + secondary roles, and transient lifetimes. Provider truth stays in each feature;
/// features submit typed activities and this coordinator never performs provider I/O.
@MainActor
public final class ActivityCoordinator: ObservableObject {
    public let notifications: NotificationCoordinator

    /// The activity that owns the collapsed presentation.
    @Published public private(set) var primary: NotchActivity?
    /// One other live activity shown as a small chip, when the primary's presentation allows it.
    @Published public private(set) var secondary: NotchActivity?
    /// Every live activity, best-ranked first (primary is not necessarily first after a promotion).
    @Published public private(set) var liveActivities: [NotchActivity] = []
    /// The best baseline (persistent/condition) activity; transients interrupt it without replacing it.
    @Published public private(set) var persistentActivity: NotchActivity?
    /// The primary activity when it is transient.
    @Published public private(set) var activeTransient: NotchActivity?
    /// Live transients waiting underneath the primary.
    @Published public private(set) var queueCount = 0
    @Published public private(set) var presentationMode: NotchPresentationMode = .none

    public var activeActivity: NotchActivity? { primary }
    public var foregroundActivity: NotchActivity? { primary }
    public var underlyingActivity: NotchActivity? { persistentActivity }
    public var transientActivity: NotchActivity? { activeTransient }

    /// Presentation compatibility is independent of which transient wins priority.
    public var retainsMediaPresentation: Bool { mediaBaseline != nil }

    /// Fresh expansion policy is independent of transient presentation priority.
    /// A retained paused track is useful on Home, but does not make Music the default.
    public var preferredExpandedPage: NotchPage {
        if let activeTransient,
           activeTransient.kind == .media || activeTransient.destination == .music {
            return .music
        }
        // Only playback on this Mac makes Music the fresh default; remote Connect playback
        // (e.g. a phone) opens on Home.
        if mediaBaseline?.kind == .media,
           case .mediaPlayback(isPlaying: true, isLocal: true) = mediaBaseline?.payload {
            return .music
        }
        return .home
    }

    /// The live Music baseline, even when another baseline (a transfer) currently ranks higher.
    private var mediaBaseline: NotchActivity? {
        liveActivities.first { $0.lifetime.isBaseline && $0.presentationStyle == .mediaSides }
    }

    public func contains(id: UUID) -> Bool {
        entries.values.contains { $0.activity.id == id }
    }

    struct Entry {
        var activity: NotchActivity
        var notification: NotchNotification?
        /// Order of the last meaningful update; the newest equal-priority transient wins.
        var sequence: UInt64
        /// Transients only. `expiresAt` is stamped from the injected clock and cleared by
        /// every meaningful update, so an earlier deadline can never remove newer state.
        var duration: Duration?
        var createdAt: Date?
        var expiresAt: Date?
    }

    private var entries: [NotchActivityKey: Entry] = [:]
    private var primaryKey: NotchActivityKey?
    /// A user-selected secondary holds the primary role until the next interruption.
    private var promotedKey: NotchActivityKey?
    private var nextSequence: UInt64 = 0
    private let clock: any AppClock
    private var lifetimeTask: Task<Void, Never>?
    private var lifetimeGeneration = 0

    public init(clock: any AppClock) {
        self.clock = clock
        notifications = NotificationCoordinator()
        notifications.activities = self
    }

    deinit { lifetimeTask?.cancel() }

    // MARK: Submission

    /// Submits or updates a generic activity. Persistent/condition activities have no deadline;
    /// transient ones expire `duration` after their latest meaningful update (never if nil).
    public func present(_ activity: NotchActivity) {
        upsert(activity, notification: nil, duration: activity.lifetime.isBaseline ? nil : activity.duration)
    }

    /// Returns whether the notification is now the primary presentation. A notification that
    /// cannot present yet stays live underneath until its own absolute deadline.
    @discardableResult
    func presentNotification(_ notification: NotchNotification) -> Bool {
        var incoming = notification
        let key = NotchActivityKey(notification.coalescingKey)
        // Calendar reminders keep discrete identities; other sources update in place.
        if let existing = entries[key]?.notification, incoming.presentationStyle != .calendar {
            // Repeated service snapshots are not meaningful changes and never extend a lifetime.
            if existing.content == incoming.content, existing.kind == incoming.kind {
                return primaryKey == key
            }
            incoming.id = existing.id
        }
        upsert(incoming.activity, notification: incoming, duration: incoming.duration)
        return primaryKey == key
    }

    private func upsert(_ activity: NotchActivity, notification: NotchNotification?, duration: Duration?) {
        let key = activity.key
        let isTransient = !activity.lifetime.isBaseline
        if var entry = entries[key] {
            if notification == nil, entry.notification == nil,
               entry.activity.hasSamePresentation(as: activity) { return }
            let wasTransient = !entry.activity.lifetime.isBaseline
            entry.activity = activity
            entry.notification = notification
            if isTransient {
                entry.sequence = takeSequence()
                entry.duration = duration
                entry.createdAt = nil
                entry.expiresAt = nil
            } else {
                // One identity may change role (transfer progress ↔ result): a baseline has no deadline.
                entry.duration = nil
                entry.createdAt = nil
                entry.expiresAt = nil
            }
            entries[key] = entry
            resolve()
            if isTransient || wasTransient { scheduleLifetimes() }
            return
        } else {
            entries[key] = Entry(activity: activity, notification: notification,
                                 sequence: takeSequence(), duration: isTransient ? duration : nil)
        }
        resolve()
        if isTransient { scheduleLifetimes() }
    }

    // MARK: Removal / selection

    public func dismissActive() {
        guard let key = activeTransient?.key else { return }
        remove { $0.activity.key == key }
    }

    public func dismiss(id: UUID) {
        remove { $0.activity.id == id }
    }

    public func dismiss(key: NotchActivityKey) {
        remove { $0.activity.key == key }
    }

    public func dismiss(kind: NotchActivityKind) {
        remove { $0.activity.kind == kind }
    }

    /// Makes the secondary (baseline) activity primary. The previous primary stays live as the secondary.
    public func promoteSecondary() {
        guard let key = secondary?.key else { return }
        promotedKey = key
        resolve()
    }

    public func clearQueue() {
        remove { !$0.activity.lifetime.isBaseline && $0.activity.key != primaryKey }
    }

    public func clearAll() {
        entries.removeAll()
        promotedKey = nil
        resolve()
        scheduleLifetimes()
    }

    private func remove(where predicate: (Entry) -> Bool) {
        let removed = entries.filter { predicate($0.value) }
        guard !removed.isEmpty else { return }
        removed.keys.forEach { entries.removeValue(forKey: $0) }
        resolve()
        if removed.values.contains(where: { $0.duration != nil }) { scheduleLifetimes() }
    }

    private func takeSequence() -> UInt64 {
        nextSequence &+= 1
        return nextSequence
    }

    // MARK: Arbitration

    private func resolve() {
        if let key = promotedKey, entries[key] == nil { promotedKey = nil }
        var ranked = entries.values.sorted(by: ActivityPriorityPolicy.outranks)
        let interruption = ranked.first.flatMap { $0.activity.lifetime.isBaseline ? nil : $0 }
        // An interruption ends a user promotion: afterwards the primary is re-ranked from the
        // activities that are live now, never restored from a stale choice.
        if interruption != nil { promotedKey = nil }
        let primaryEntry = interruption ?? promotedKey.flatMap { entries[$0] } ?? ranked.first
        // Replaceable feedback that does not hold the notch is dropped, never resumed later.
        let stale = ranked.filter {
            $0.activity.key != primaryEntry?.activity.key && ActivityPriorityPolicy.isReplaceable($0)
        }
        if !stale.isEmpty {
            stale.forEach { entries.removeValue(forKey: $0.activity.key) }
            ranked.removeAll { entry in stale.contains { $0.activity.key == entry.activity.key } }
        }
        let baseline = ranked.first { $0.activity.lifetime.isBaseline }
        let secondaryEntry = primaryEntry.flatMap { ActivityPriorityPolicy.secondary(beside: $0, among: ranked) }
        let transient = primaryEntry.flatMap { $0.activity.lifetime.isBaseline ? nil : $0 }
        // The primary's content when it has any: every transient, or a baseline notification
        // (an active transfer). Music draws its own flanks and has none.
        let presented = primaryEntry.flatMap { $0.notification != nil || transient != nil ? $0 : nil }
        primaryKey = primaryEntry?.activity.key

        // The notification slot is synchronised first so the shell never observes a
        // primary without its content (no intermediate empty frame).
        notifications.show(presented?.notification, createdAt: presented?.createdAt,
                           expiresAt: presented?.expiresAt)
        let live = ranked.map(\.activity)
        if liveActivities != live { liveActivities = live }
        if primary != primaryEntry?.activity { primary = primaryEntry?.activity }
        if activeTransient != transient?.activity { activeTransient = transient?.activity }
        if persistentActivity != baseline?.activity { persistentActivity = baseline?.activity }
        if secondary != secondaryEntry?.activity { secondary = secondaryEntry?.activity }
        let waiting = ranked.count { !$0.activity.lifetime.isBaseline && $0.activity.key != primaryKey }
        if queueCount != waiting { queueCount = waiting }
        let media = ranked.first { $0.activity.lifetime.isBaseline && $0.activity.presentationStyle == .mediaSides }
        let mode = Self.presentationMode(persistent: media?.activity, best: baseline?.activity,
                                         transient: presented?.activity)
        if presentationMode != mode { presentationMode = mode }
    }

    /// `persistent`: live Music (kept under compact content); `best`: the highest baseline, which
    /// decides whether a Calendar banner shows Music in its top row or leaves room for a chip.
    private static func presentationMode(
        persistent: NotchActivity?,
        best: NotchActivity?,
        transient: NotchActivity?
    ) -> NotchPresentationMode {
        guard let transient else {
            return persistent?.presentationStyle == .mediaSides ? .mediaSides : .none
        }
        switch transient.presentationStyle {
        case .none: return persistent?.presentationStyle == .mediaSides ? .mediaSides : .none
        case .mediaSides: return .mediaSides
        case .downwardBanner:
            return transient.family == .calendar && best?.presentationStyle == .mediaSides
                ? .combined
                : .downwardBanner
        case .compactHUD: return persistent?.presentationStyle == .mediaSides ? .combined : .compactHUD
        }
    }

    // MARK: Lifetimes

    /// One task serves every transient deadline. Any change reschedules it under a new
    /// generation, so a stale wake-up can never expire state it did not see.
    private func scheduleLifetimes() {
        lifetimeTask?.cancel()
        lifetimeTask = nil
        lifetimeGeneration &+= 1
        let generation = lifetimeGeneration
        guard entries.values.contains(where: { $0.duration != nil }) else { return }

        lifetimeTask = Task { [weak self, clock] in
            let now = await clock.now()
            guard let delay = self?.stampDeadlines(at: now, generation: generation) else { return }
            do { try await clock.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            let firedAt = await clock.now()
            self?.expire(at: firedAt, generation: generation)
        }
    }

    private func stampDeadlines(at now: Date, generation: Int) -> Duration? {
        guard generation == lifetimeGeneration else { return nil }
        var stamped = false
        for (key, entry) in entries {
            guard let duration = entry.duration, entry.expiresAt == nil else { continue }
            entries[key]?.createdAt = now
            entries[key]?.expiresAt = now.addingTimeInterval(duration.timeInterval)
            stamped = true
        }
        if stamped { resolve() }
        guard let next = entries.values.compactMap(\.expiresAt).min() else { return nil }
        return .seconds(max(0, next.timeIntervalSince(now)))
    }

    private func expire(at now: Date, generation: Int) {
        guard generation == lifetimeGeneration else { return }
        let expired = entries.filter { $0.value.expiresAt.map { $0 <= now } == true }
        expired.keys.forEach { entries.removeValue(forKey: $0) }
        if !expired.isEmpty { resolve() }
        scheduleLifetimes()
    }

#if DEBUG
    /// Concise coordinator state for developer tools; not logged.
    public var debugSummary: String {
        let rows = entries.values.sorted(by: ActivityPriorityPolicy.outranks).map { entry in
            let key = entry.activity.key
            let role = key == primaryKey ? "P" : (key == secondary?.key ? "S" : "·")
            let deadline = entry.expiresAt.map { " until \($0.formatted(date: .omitted, time: .standard))" } ?? ""
            return "\(role) \(key) [\(entry.activity.priority), \(entry.activity.lifetime)]\(deadline)"
        }
        return rows.isEmpty ? "No live activities" : rows.joined(separator: "\n")
    }
#endif
}

extension NotchActivity {
    var family: NotchActivityFamily { kind.family }
}

extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
