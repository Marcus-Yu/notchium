import SwiftUI

/// Soft, desaturated tones for the always-black notch, in the family of the Focus Timer's own
/// palette (its focus blue is `sky`). Values are fixed sRGB: the notch never follows the Mac's
/// light/dark appearance the way `Color.red` does.
///
/// Usage rules: a page's identity tone reaches its content through SwiftUI's native `.tint`.
/// Color marks the current selection, active modes and live state only; text, primary transport
/// and inactive chrome stay white. Every tone clears 7:1 against black.
public enum NotchPalette {
    // Page identities.
    public static let rose = rgb(236, 138, 156)
    public static let sky = rgb(130, 177, 245)
    public static let teal = rgb(112, 196, 200)
    public static let lavender = rgb(178, 160, 232)
    public static let sand = rgb(226, 196, 130)

    // Status: Apple's semantic hues, softened so they sit quietly on black.
    public static let green = rgb(110, 206, 140)
    public static let red = rgb(250, 118, 108)
    public static let orange = rgb(255, 176, 92)

    /// Fill behind a tinted glyph: a selected tab or an active toggle.
    public static let selectionFillOpacity = 0.18
    /// Hover wash for an otherwise transparent control.
    public static let hoverFillOpacity = 0.09

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255)
    }
}

/// The meaning of each status color inside activities and notifications.
public enum NotchStatusColor {
    public static let success = NotchPalette.green
    public static let warning = NotchPalette.orange
    public static let failure = NotchPalette.red
}
