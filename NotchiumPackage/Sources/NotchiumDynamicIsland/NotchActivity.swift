import Foundation

public enum NotchActivityPriority: Int, CaseIterable, Comparable, Sendable {
    case low = 100
    case medium = 200
    case high = 300
    case critical = 400

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum NotchActivityFamily: Hashable, Sendable {
    case media
    case calendar
    case audio
    case other(NotchActivityKind)
}

public enum NotchActivityPresentationStyle: Equatable, Sendable {
    case none
    case mediaSides
    case downwardBanner
    case compactHUD
}

public enum NotchPresentationMode: Equatable, Sendable {
    case none
    case mediaSides
    case downwardBanner
    case compactHUD
    case combined
}

/// How long an activity lives. Only `.transient` carries a coordinator-owned deadline;
/// persistent and condition activities live exactly as long as their provider reports them.
public enum NotchActivityLifetime: Equatable, Sendable {
    /// Ongoing provider state, e.g. active Spotify playback.
    case persistent
    /// A system condition that holds until it clears, e.g. a future low-battery condition.
    case condition
    /// One event with an absolute lifetime, e.g. volume, output change, reminder, utility result.
    case transient

    /// Persistent and condition activities form the baseline that transients interrupt.
    public var isBaseline: Bool { self != .transient }
}

/// Stable identity. Repeated events with the same key update one activity instead of stacking.
/// Keys are namespaced by source ("audio.level", "calendar.<event>", "media.spotify").
public struct NotchActivityKey: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static let media = Self("media.spotify")
}

/// The small representation used when an activity is the secondary (not primary) activity.
public enum NotchActivityMinimal: Equatable, Sendable {
    /// Current artwork, drawn by the media renderer.
    case artwork
    case glyph(NotchCompactActivity.Glyph, tint: NotchCompactActivity.Tint)
    /// A small ring; nil fraction is indeterminate. Used by persistent transfers.
    case progress(Double?)
    /// A ring that empties toward a deadline; drawn from the deadline, never re-submitted per tick.
    case countdown(NotchCountdown)
}

public enum NotchActivityDestination: Equatable, Sendable {
    case music
    case calendar
    case audio
    case shelf
    case pomodoro
}

public enum NotchActivityPayload: Equatable, Sendable {
    case none
    /// `isLocal`: this Mac is the playing Spotify device (not a phone or other Connect device).
    case mediaPlayback(isPlaying: Bool, isLocal: Bool = true)
    case audio(NotchAudioHUD)
}

public struct NotchActivity: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let key: NotchActivityKey
    public let kind: NotchActivityKind
    public let title: String
    public let subtitle: String?
    public let priority: NotchActivityPriority
    public let presentationStyle: NotchActivityPresentationStyle
    public let lifetime: NotchActivityLifetime
    public let isDismissible: Bool
    public let destination: NotchActivityDestination?
    public let timestamp: Date
    public let duration: Duration?
    public let payload: NotchActivityPayload
    public let minimal: NotchActivityMinimal?

    public init(id: UUID, key: NotchActivityKey? = nil, kind: NotchActivityKind, title: String,
                subtitle: String?, priority: NotchActivityPriority? = nil,
                presentationStyle: NotchActivityPresentationStyle? = nil,
                lifetime: NotchActivityLifetime? = nil,
                isDismissible: Bool = true,
                destination: NotchActivityDestination? = nil,
                usesDefaultDestination: Bool = true,
                timestamp: Date = .now,
                duration: Duration?,
                payload: NotchActivityPayload = .none,
                minimal: NotchActivityMinimal? = nil) {
        self.id = id
        self.key = key ?? NotchActivityKey(id.uuidString)
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.priority = priority ?? kind.priority
        self.presentationStyle = presentationStyle ?? kind.defaultPresentationStyle
        self.lifetime = lifetime ?? (kind == .media ? .persistent : .transient)
        self.isDismissible = isDismissible
        self.destination = destination ?? (usesDefaultDestination ? Self.defaultDestination(for: kind) : nil)
        self.timestamp = timestamp
        self.duration = duration
        self.payload = payload
        self.minimal = minimal
    }

    /// Equal apart from the event time: a repeated provider snapshot, not a meaningful update.
    func hasSamePresentation(as other: Self) -> Bool {
        id == other.id && key == other.key && kind == other.kind && title == other.title
            && subtitle == other.subtitle && priority == other.priority
            && presentationStyle == other.presentationStyle && lifetime == other.lifetime
            && isDismissible == other.isDismissible && destination == other.destination
            && duration == other.duration && payload == other.payload && minimal == other.minimal
    }

    private static func defaultDestination(for kind: NotchActivityKind) -> NotchActivityDestination? {
        switch kind {
        case .media: .music
        case .calendar, .meeting: .calendar
        case .audioDevice, .systemHUD: .audio
        default: nil
        }
    }
}
