public enum NotchPage: String, CaseIterable, Identifiable, Sendable {
    case home, music, calendar, audio, shelf
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Home"
        case .music: "Music"
        case .calendar: "Calendar"
        case .audio: "Audio"
        case .shelf: "Shelf"
        }
    }

    public var symbol: String {
        switch self {
        case .home: "house"
        case .music: "music.note"
        case .calendar: "calendar"
        case .audio: "speaker.wave.2"
        case .shelf: "tray"
        }
    }
}
