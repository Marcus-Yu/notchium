public enum NotchPage: String, CaseIterable, Identifiable, Sendable {
    case home, media, system, utilities, focus
    public var id: String { rawValue }
}
