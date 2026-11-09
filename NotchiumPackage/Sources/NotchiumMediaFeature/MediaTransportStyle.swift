import NotchiumDesignSystem
import SwiftUI

extension MediaFeatureModel {
    /// The tone Music speaks in: a soft version of the artwork's color, or Music's own rose for
    /// neutral covers. It marks Music's tab and active modes, never the transport or progress.
    var musicAccent: Color { accentColor ?? NotchPalette.rose }
}

/// Transport appearance for the Music page. Play/Pause and progress keep their original white;
/// the accent appears only while a mode toggle (shuffle, repeat) is on.
enum MediaTransportStyle {
    static func glyph(active: Bool, available: Bool, opacity: Double) -> AnyShapeStyle {
        active && available ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(opacity))
    }

    struct Disc: View {
        let primary: Bool
        let active: Bool

        var body: some View {
            if primary {
                Circle().fill(.white.opacity(0.18))
            } else {
                Circle().fill(.tint.opacity(active ? NotchPalette.selectionFillOpacity : 0))
            }
        }
    }
}
