public enum NotchActivityKind: String, CaseIterable, Hashable, Sendable {
    case media, charging, battery, audioDevice, systemHUD, calendar
    case meeting, download, screenshot, clipboard, focus, notification

    public var priority: NotchActivityPriority {
        switch self {
        case .media, .systemHUD: .low
        case .charging, .audioDevice, .download, .screenshot, .calendar: .medium
        case .focus, .battery, .meeting, .clipboard: .high
        case .notification: .critical
        }
    }

    public var family: NotchActivityFamily {
        switch self {
        case .media: .media
        case .calendar, .meeting: .calendar
        case .audioDevice, .systemHUD: .audio
        default: .other(self)
        }
    }

    public var defaultPresentationStyle: NotchActivityPresentationStyle {
        switch self {
        case .media: .mediaSides
        case .audioDevice, .systemHUD: .compactHUD
        default: .downwardBanner
        }
    }
}
