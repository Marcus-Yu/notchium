public enum NotchActivityKind: String, CaseIterable, Sendable {
    case media, charging, battery, audioDevice, systemHUD, calendar
    case meeting, download, screenshot, clipboard, focus, notification

    public var priority: Int {
        switch self {
        case .systemHUD: 10
        case .media: 20
        case .charging, .audioDevice: 30
        case .download, .screenshot: 40
        case .calendar: 15
        case .focus: 60
        case .battery: 70
        case .meeting, .clipboard: 80
        case .notification: 100
        }
    }
}
