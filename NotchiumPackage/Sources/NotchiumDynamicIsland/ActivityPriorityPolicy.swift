/// The single semantic priority table for production activities and notifications.
/// Persistent playback is a separate baseline, never a competing transient slot.
public enum ActivityPriorityPolicy {
    public static func priority(for kind: NotchNotification.Kind) -> NotchActivityPriority {
        switch kind {
        case .reminder5: .high
        case .reminder30, .reminder60, .outputDeviceChanged: .medium
        case .volume, .mute: .low
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
}
