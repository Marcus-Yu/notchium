import Foundation

/// Calendar reminders, local Audio feedback, and low-priority utility results.
public struct NotchNotification: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case reminder60, reminder30, reminder5
        case volume, mute, outputDeviceChanged
        case actionSucceeded, actionFailed, reminderAdded
        case charging, lowBattery, criticalBattery, powerDisconnected
        case transferActive, transferFinished, transferFailed
        case screenshot, shelfAdded
        case focusTimer, focusTimerBesideMusic, focusTimerComplete, focusModeChanged

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
            case .criticalBattery: .seconds(6)
            case .powerDisconnected: .milliseconds(1750)
            // Persistent while any transfer runs; the coordinator ignores it for baselines.
            case .transferActive: .seconds(0)
            case .transferFinished: .milliseconds(2500)
            case .transferFailed: .seconds(3)
            case .screenshot: .seconds(4)
            case .shelfAdded: .milliseconds(1750)
            // Persistent while the timer runs, like an active transfer.
            case .focusTimer, .focusTimerBesideMusic: .seconds(0)
            case .focusTimerComplete: .seconds(3)
            case .focusModeChanged: .seconds(2)
            }
        }
    }
    /// `.compact` occupies the notch's two sides at collapsed height; the others grow downward.
    public enum PresentationStyle: Equatable, Sendable { case calendar, feedback, compact }
    public enum Action: Equatable, Sendable { case calendar, audio, shelf, pomodoro, join(URL), none }
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
    /// `.persistent` notifications (active transfers) live until their source replaces them.
    public let lifetime: NotchActivityLifetime
    /// Secondary-chip form; only meaningful for persistent notifications.
    public let minimal: NotchActivityMinimal?

    public init(id: UUID = UUID(), kind: Kind,
                duration: Duration? = nil, dismissible: Bool = true, coalescingKey: String,
                action: Action, presentationStyle: PresentationStyle, content: Content,
                lifetime: NotchActivityLifetime = .transient, minimal: NotchActivityMinimal? = nil) {
        self.lifetime = lifetime
        self.minimal = minimal
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
        // Connect, disconnect and output switch share one route identity: one physical
        // transition updates one activity instead of stacking overlapping cards.
        let output = hud.isDeviceTransition
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

    /// Every Mac battery state shares the "battery" identity: severity changes update one activity.
    public static func criticalBattery(level: Double) -> Self {
        Self(kind: .criticalBattery, coalescingKey: "battery", action: .none, presentationStyle: .compact,
             content: .compact(.criticalBattery(level: level)))
    }

    public static func powerDisconnected(level: Double) -> Self {
        Self(kind: .powerDisconnected, coalescingKey: "battery", action: .none, presentationStyle: .compact,
             content: .compact(.powerDisconnected(level: level)))
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
        case .charging, .powerDisconnected: .charging
        case .lowBattery, .criticalBattery: .battery
        case .transferActive, .transferFinished, .transferFailed: .download
        case .screenshot: .screenshot
        case .shelfAdded: .clipboard
        case .focusTimer, .focusTimerBesideMusic, .focusTimerComplete: .pomodoro
        case .focusModeChanged: .focus
        default: .systemHUD
        }
        let destination: NotchActivityDestination? = switch action {
        case .calendar, .join: .calendar
        case .audio: .audio
        case .shelf: .shelf
        case .pomodoro: .pomodoro
        case .none: nil
        }
        return NotchActivity(id: id, key: NotchActivityKey(coalescingKey), kind: activityKind,
            title: title, subtitle: subtitle, priority: priority,
            presentationStyle: presentationStyle == .calendar ? .downwardBanner : .compactHUD,
            lifetime: lifetime, isDismissible: dismissible,
            destination: destination, usesDefaultDestination: false,
            duration: lifetime.isBaseline ? nil : duration, payload: payload, minimal: minimal)
    }
}
