public enum NotchPage: String, CaseIterable, Identifiable, Sendable {
    case music, calendar
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .music: "Music"
        case .calendar: "Calendar"
        }
    }

    public var symbol: String {
        switch self {
        case .music: "music.note"
        case .calendar: "calendar"
        }
    }
}
