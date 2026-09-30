import Foundation

/// Calendar reminders, local Audio feedback, and low-priority utility results.
public struct NotchNotification: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case reminder60, reminder30, reminder5
        case volume, mute, outputDeviceChanged
        case actionSucceeded, actionFailed, reminderAdded
        case charging, lowBattery

        public var defaultDuration: Duration {
            switch self {
            case .reminder60, .reminder30, .reminder5: .seconds(5)
            case .outputDeviceChanged: .milliseconds(2500)
            case .volume, .mute: .milliseconds(1750)
            case .actionSucceeded: .milliseconds(1500)
            case .actionFailed: .seconds(3)
            case .reminderAdded: .seconds(2)
            case .charging: .milliseconds(2500)
            case .lowBattery: .seconds(4)
            }
        }
    }
    /// `.compact` occupies the notch's two sides at collapsed height; the others grow downward.
    public enum PresentationStyle: Equatable, Sendable { case calendar, feedback, compact }
    public enum Action: Equatable, Sendable { case calendar, audio, join(URL), none }
    public enum Content: Equatable, Sendable {
        case calendar(title: String, status: String)
        case audio(NotchAudioHUD)
        case feedback(title: String, symbol: String)
        case compact(NotchCompactActivity)

        /// Every audio HUD is rendered as a compact activity beside the notch.
        public var compactActivity: NotchCompactActivity? {
            switch self {
            case let .audio(hud): NotchCompactActivity(hud)
            case let .compact(activity): activity
            case .calendar, .feedback: nil
            }
        }
    }

    public var id: UUID
    public let kind: Kind
    public var priority: NotchActivityPriority { ActivityPriorityPolicy.priority(for: kind) }
    public let duration: Duration
    public let dismissible: Bool
    public let coalescingKey: String
    public let action: Action
    public let presentationStyle: PresentationStyle
    public let content: Content

    public init(id: UUID = UUID(), kind: Kind,
                duration: Duration? = nil, dismissible: Bool = true, coalescingKey: String,
                action: Action, presentationStyle: PresentationStyle, content: Content) {
        self.id = id
        self.kind = kind
        self.duration = duration ?? kind.defaultDuration
        self.dismissible = dismissible
        self.coalescingKey = coalescingKey
        self.action = action
        self.presentationStyle = presentationStyle
        self.content = content
    }

    public static func audio(_ hud: NotchAudioHUD) -> Self {
        let output = hud.kind == .outputChanged
        return Self(kind: output ? .outputDeviceChanged : (hud.isMuted ? .mute : .volume),
                    coalescingKey: output ? "audio.output" : "audio.level",
                    action: .audio, presentationStyle: .compact, content: .audio(hud))
    }

    public static func charging(level: Double) -> Self {
        Self(kind: .charging, coalescingKey: "battery", action: .none, presentationStyle: .compact,
             content: .compact(.charging(level: level)))
    }

    public static func lowBattery(level: Double) -> Self {
        Self(kind: .lowBattery, coalescingKey: "battery", action: .none, presentationStyle: .compact,
             content: .compact(.lowBattery(level: level)))
    }

    public static func feedback(_ title: String, kind: Kind, key: String) -> Self {
        Self(kind: kind, coalescingKey: key, action: .none, presentationStyle: .feedback,
             content: .feedback(title: title, symbol: kind == .actionFailed ? "exclamationmark.circle" : "checkmark.circle"))
    }

    var activity: NotchActivity {
        let title: String
        let subtitle: String?
        let payload: NotchActivityPayload
        switch content {
        case let .calendar(eventTitle, status):
            title = eventTitle; subtitle = status; payload = .none
        case let .feedback(message, _):
            title = message; subtitle = nil; payload = .none
        case let .audio(hud):
            title = hud.deviceName; subtitle = hud.isMuted ? "Muted" : "Volume"
            payload = .audio(hud)
        case let .compact(activity):
            title = activity.title; subtitle = nil; payload = .none
        }
        let activityKind: NotchActivityKind = switch kind {
        case .reminder60, .reminder30, .reminder5: .calendar
        case .outputDeviceChanged: .audioDevice
        case .charging: .charging
        case .lowBattery: .battery
        default: .systemHUD
        }
        let destination: NotchActivityDestination? = switch action {
        case .calendar, .join: .calendar
        case .audio: .audio
        case .none: nil
        }
        return NotchActivity(id: id, key: NotchActivityKey(coalescingKey), kind: activityKind,
            title: title, subtitle: subtitle, priority: priority,
            presentationStyle: presentationStyle == .calendar ? .downwardBanner : .compactHUD,
            lifetime: .transient, isDismissible: dismissible,
            destination: destination, usesDefaultDestination: false,
            duration: duration, payload: payload, minimal: minimal)
    }

    /// Compact activities reuse their own glyph; utility text results have no minimal form.
    private var minimal: NotchActivityMinimal? {
        switch content {
        case .calendar: .glyph(.symbol("calendar"), tint: .primary)
        case .feedback: nil
        case .audio, .compact:
            content.compactActivity.map { .glyph($0.glyph, tint: $0.tint) }
        }
    }
}
