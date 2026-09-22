import SwiftUI

/// Opaque at rest, independent of the system's dark glass appearance.
struct CalendarJoinButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.white, in: Capsule())
            .fixedSize()
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : (isHovered ? 1.03 : 1)))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
