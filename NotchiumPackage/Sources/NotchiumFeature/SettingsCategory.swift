import Foundation

/// Stable navigation identity; settings remain owned by their existing feature models.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, home, media, audio, calendar, clipboard, focus, caffeine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .home: "Home Page"
        case .media: "Media"
        case .audio: "Audio"
        case .calendar: "Calendar"
        case .clipboard: "Clipboard"
        case .focus: "Focus"
        case .caffeine: "Caffeine"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .home: "house"
        case .media: "music.note"
        case .audio: "speaker.wave.2"
        case .calendar: "calendar"
        case .clipboard: "doc.on.clipboard"
        case .focus: "timer"
        case .caffeine: "cup.and.saucer"
        }
    }
}
