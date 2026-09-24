import Foundation

public enum NotchActivityPriority: Int, CaseIterable, Comparable, Sendable {
    case low = 100
    case medium = 200
    case high = 300
    case critical = 400

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(legacyValue: Int) {
        switch legacyValue {
        case ..<25: self = .low
        case 25..<60: self = .medium
        case 60..<100: self = .high
        default: self = .critical
        }
    }
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

public enum NotchActivityLifetime: Equatable, Sendable {
    case persistent
    case transient
}

public enum NotchActivityDestination: Equatable, Sendable {
    case music
    case calendar
    case audio
}

public enum NotchActivityPayload: Equatable, Sendable {
    case none
    case audio(NotchAudioHUD)
}

public struct NotchActivity: Identifiable, Equatable, Sendable {
    public let id: UUID
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

    public init(id: UUID, kind: NotchActivityKind, title: String,
                subtitle: String?, priority: NotchActivityPriority? = nil,
                presentationStyle: NotchActivityPresentationStyle? = nil,
                lifetime: NotchActivityLifetime? = nil,
                isDismissible: Bool = true,
                destination: NotchActivityDestination? = nil,
                timestamp: Date = .now,
                duration: Duration?,
                payload: NotchActivityPayload = .none) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.priority = priority ?? kind.priority
        self.presentationStyle = presentationStyle ?? kind.defaultPresentationStyle
        self.lifetime = lifetime ?? (kind == .media ? .persistent : .transient)
        self.isDismissible = isDismissible
        self.destination = destination ?? Self.defaultDestination(for: kind)
        self.timestamp = timestamp
        self.duration = duration
        self.payload = payload
    }

    /// Keeps older fixtures source-compatible while production uses typed priorities.
    public init(id: UUID, kind: NotchActivityKind, title: String,
                subtitle: String?, priority: Int, duration: Duration?) {
        self.init(id: id, kind: kind, title: title, subtitle: subtitle,
                  priority: NotchActivityPriority(legacyValue: priority), duration: duration)
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
