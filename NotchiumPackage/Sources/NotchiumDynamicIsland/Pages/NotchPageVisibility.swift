import NotchiumDesignSystem
import SwiftUI

/// Retained pages fade through the shell's black background instead of drawing
/// two player layouts over one another. Input and lifecycle still follow selection.
struct NotchPageVisibility: ViewModifier {
    let isVisible: Bool
    @NotchReducedMotion private var reduceMotion

    private var animation: Animation {
        let exit = reduceMotion ? 0.04 : 0.08
        let entry = reduceMotion ? 0.06 : 0.12
        // Every outgoing page finishes within this interval, including after a
        // reversal. SwiftUI retargets opacity from its live presentation value.
        return .easeOut(duration: isVisible ? entry : exit)
            .delay(isVisible ? exit : 0)
    }

    func body(content: Content) -> some View {
        content.animation(animation) { page in
            page.opacity(isVisible ? 1 : 0)
        }
    }
}
