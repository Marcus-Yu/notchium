/// The single semantic priority table and arbitration order for every activity.
///
/// 1. Transients (events) interrupt baselines (persistent/condition state such as Music):
///    a volume change briefly takes the notch, then Music returns without being recreated.
/// 2. Among transients, higher priority wins; at equal priority the latest update wins.
///    Interrupted transients stay live underneath until their own absolute deadline.
/// 3. Among baselines, higher priority wins; at equal priority the earliest stays put.
/// 4. The stable key breaks any remaining tie, so ordering is always deterministic.
public enum ActivityPriorityPolicy {
    public static func priority(for kind: NotchNotification.Kind) -> NotchActivityPriority {
        switch kind {
        case .reminder5, .lowBattery: .high
        case .reminder30, .reminder60, .outputDeviceChanged, .charging: .medium
        case .volume, .mute, .actionSucceeded, .actionFailed, .reminderAdded: .low
        }
    }

    public static func priority(for kind: NotchActivityKind) -> NotchActivityPriority {
        switch kind {
        case .media, .systemHUD: .low
        case .charging, .audioDevice, .download, .screenshot, .calendar: .medium
        case .focus, .battery, .meeting, .clipboard: .high
        case .notification: .critical
        }
    }

    static func outranks(_ lhs: ActivityCoordinator.Entry, _ rhs: ActivityCoordinator.Entry) -> Bool {
        let left = lhs.activity, right = rhs.activity
        if left.lifetime.isBaseline != right.lifetime.isBaseline { return !left.lifetime.isBaseline }
        if left.priority != right.priority { return left.priority > right.priority }
        if lhs.sequence != rhs.sequence {
            return left.lifetime.isBaseline ? lhs.sequence < rhs.sequence : lhs.sequence > rhs.sequence
        }
        return left.key.rawValue < right.key.rawValue
    }

    /// A secondary chip sits beside compact side content only. Downward banners already keep
    /// Music in the top row, and brief replaceable HUDs (volume) never spawn extra chrome.
    static func allowsSecondary(beside primary: ActivityCoordinator.Entry) -> Bool {
        // Media publishes a minimal form only while its collapsed flanks are really visible.
        if primary.activity.presentationStyle == .mediaSides { return primary.activity.minimal != nil }
        guard primary.notification?.presentationStyle == .compact else { return false }
        return primary.activity.priority > .low
    }
}
