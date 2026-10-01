public enum NotchPage: String, CaseIterable, Identifiable, Sendable {
    case home, music, calendar, pomodoro, audio, shelf
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Home"
        case .music: "Music"
        case .calendar: "Calendar"
        case .pomodoro: "Focus Timer"
        case .audio: "Audio"
        case .shelf: "Shelf"
        }
    }

    public var symbol: String {
        switch self {
        case .home: "house"
        case .music: "music.note"
        case .calendar: "calendar"
        case .pomodoro: "timer"
        case .audio: "speaker.wave.2"
        case .shelf: "tray"
        }
    }
}
