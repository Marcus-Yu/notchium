import Foundation

/// Stage 9 is deliberately limited to Calendar and local system Audio feedback.
public struct NotchNotification: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case reminder60, reminder30, reminder5
        case volume, mute, outputDeviceChanged
    }
    public enum PresentationStyle: Equatable, Sendable { case calendar, audio }
    public enum Action: Equatable, Sendable { case calendar, audio, join(URL) }
    public enum Content: Equatable, Sendable {
        case calendar(title: String, status: String)
        case audio(NotchAudioHUD)
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
                duration: Duration, dismissible: Bool = true, coalescingKey: String,
                action: Action, presentationStyle: PresentationStyle, content: Content) {
        self.id = id
        self.kind = kind
        self.duration = duration
        self.dismissible = dismissible
        self.coalescingKey = coalescingKey
        self.action = action
        self.presentationStyle = presentationStyle
        self.content = content
    }

    public static func audio(_ hud: NotchAudioHUD) -> Self {
        let output = hud.kind == .outputChanged
        return Self(kind: output ? .outputDeviceChanged : (hud.isMuted ? .mute : .volume),
                    duration: output ? .seconds(3) : .milliseconds(1250),
                    coalescingKey: output ? "audio.output" : "audio.level",
                    action: .audio, presentationStyle: .audio, content: .audio(hud))
    }

    var activity: NotchActivity {
        let title: String
        let subtitle: String?
        let payload: NotchActivityPayload
        switch content {
        case let .calendar(eventTitle, status):
            title = eventTitle; subtitle = status; payload = .none
        case let .audio(hud):
            title = hud.deviceName; subtitle = hud.isMuted ? "Muted" : "Volume"
            payload = .audio(hud)
        }
        return NotchActivity(id: id,
            kind: presentationStyle == .calendar ? .calendar : (kind == .outputDeviceChanged ? .audioDevice : .systemHUD),
            title: title, subtitle: subtitle, priority: priority,
            presentationStyle: presentationStyle == .calendar ? .downwardBanner : .compactHUD,
            lifetime: .transient, isDismissible: dismissible,
            destination: presentationStyle == .calendar ? .calendar : .audio,
            duration: nil, payload: payload)
    }
}
