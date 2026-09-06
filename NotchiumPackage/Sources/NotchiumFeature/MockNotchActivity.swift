#if DEBUG
import Foundation
import NotchiumDynamicIsland

/// Synthetic events only. No provider or operating-system feature API is used.
enum MockNotchActivity: String, CaseIterable, Identifiable {
    case playSong = "Play Mock Song"
    case eventSoon = "Event in 5 min"
    case meetingSoon = "Meeting in 5 min"
    case meetingNow = "Meeting Now"
    case charging = "Start Charging"
    case batteryLow = "Battery Low"
    case batteryFull = "Battery Full"
    case connectAirPods = "Connect AirPods"
    case disconnectAirPods = "Disconnect AirPods"
    case volume = "Volume 75%"
    case brightness = "Brightness 50%"
    case startDownload = "Start Download"
    case completeDownload = "Complete Download"
    case screenshot = "Screenshot Captured"
    case urlCopied = "URL Copied"
    case imageCopied = "Image Copied"
    case focusComplete = "Focus Complete"
    case notification = "Important Notification"

    var id: String { rawValue }

    var kind: NotchActivityKind {
        switch self {
        case .playSong: .media
        case .eventSoon: .calendar
        case .meetingSoon, .meetingNow: .meeting
        case .charging: .charging
        case .batteryLow, .batteryFull: .battery
        case .connectAirPods, .disconnectAirPods: .audioDevice
        case .volume, .brightness: .systemHUD
        case .startDownload, .completeDownload: .download
        case .screenshot: .screenshot
        case .urlCopied, .imageCopied: .clipboard
        case .focusComplete: .focus
        case .notification: .notification
        }
    }

    var section: String {
        switch kind {
        case .charging, .battery: "BATTERY"
        case .audioDevice: "AIRPODS"
        case .systemHUD: "HUD"
        default: kind.rawValue.uppercased()
        }
    }

    func activity(id: UUID) -> NotchActivity {
        NotchActivity(
            id: id, kind: kind,
            title: self == .charging ? "64% · Charging" : rawValue,
            subtitle: self == .playSong ? "Mock Artist · Mock Album" : nil,
            priority: kind.priority,
            duration: self == .playSong || self == .startDownload ? nil : .seconds(3)
        )
    }
}
#endif
