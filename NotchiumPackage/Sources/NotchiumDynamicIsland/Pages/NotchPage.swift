import NotchiumDesignSystem
import SwiftUI

public enum NotchPage: String, CaseIterable, Identifiable, Sendable {
    case home, music, calendar, pomodoro, audio, shelf, teleprompter
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Home"
        case .music: "Music"
        case .calendar: "Calendar"
        case .pomodoro: "Focus Timer"
        case .audio: "Audio"
        case .shelf: "Shelf"
        case .teleprompter: "Teleprompter"
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
        case .teleprompter: "text.alignleft"
        }
    }
}

public extension NotchPage {
    /// The page's identity tone, shown on its tab when selected. Home stays neutral. Focus Timer
    /// uses its own palette's focus blue (`sky`). Music's live accent comes from the artwork
    /// (`NotchMediaRendering.accentColor`), with this tone as the fallback.
    var hue: Color {
        switch self {
        case .home: .white
        case .calendar: NotchPalette.red
        case .music: NotchPalette.rose
        case .pomodoro: NotchPalette.sky
        case .audio: NotchPalette.teal
        case .shelf: NotchPalette.lavender
        case .teleprompter: NotchPalette.sand
        }
    }

    /// The tone applied to the page's own content through `.tint`. Calendar's red marks only its
    /// tab; the page itself keeps its original neutral look.
    var contentHue: Color { self == .calendar ? .white : hue }
}
