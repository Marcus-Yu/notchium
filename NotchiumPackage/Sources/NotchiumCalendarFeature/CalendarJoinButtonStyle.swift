import NotchiumDesignSystem
import SwiftUI

/// Opaque at rest, independent of the system's dark glass appearance.
struct CalendarJoinButtonStyle: ButtonStyle {
    var height: CGFloat = 28

    @NotchReducedMotion private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(Color.white.opacity(isEnabled && configuration.isPressed ? 0.78
                                            : (isEnabled && isHovered ? 0.9 : 1)), in: Capsule())
            .fixedSize()
            // The shared press feedback; hover changes fill only, like every other notch control.
            .scaleEffect(reduceMotion || !isEnabled || !configuration.isPressed ? 1 : 0.97)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.16), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 && isEnabled }
    }
}
