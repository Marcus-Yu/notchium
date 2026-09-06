import Foundation

public struct NotchActivity: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: NotchActivityKind
    public let title: String
    public let subtitle: String?
    public let priority: Int
    public let duration: Duration?

    public init(id: UUID, kind: NotchActivityKind, title: String,
                subtitle: String?, priority: Int, duration: Duration?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.priority = priority
        self.duration = duration
    }
}
