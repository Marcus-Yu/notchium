import SwiftUI

/// Shared timing for small controls and content that changes inside a stable notch surface.
/// Shell geometry owns its separate spring; live pointer and playback coordinates stay direct.
public enum NotchMotionStyle {
    public static let reduced = Animation.easeOut(duration: 0.1)

    public static func feedback(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .smooth(duration: 0.16)
    }

    public static func contentChange(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .smooth(duration: 0.22)
    }
}
