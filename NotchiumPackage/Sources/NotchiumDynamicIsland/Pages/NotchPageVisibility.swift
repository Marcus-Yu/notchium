import NotchiumDesignSystem
import SwiftUI

/// Retained pages fade through the shell's black background instead of drawing
/// two player layouts over one another. Input and lifecycle still follow selection.
/// The incoming page settles from a slightly smaller scale, so a page change reads as the
/// new content arriving rather than a flat swap.
struct NotchPageVisibility: ViewModifier {
    let isVisible: Bool
    @NotchReducedMotion private var reduceMotion

    private var animation: Animation {
        let exit = reduceMotion ? 0.04 : 0.08
        // Every outgoing page finishes within the exit interval, including after a
        // reversal. SwiftUI retargets opacity and scale from their live presentation values.
        if isVisible {
            let entry: Animation = reduceMotion ? .easeOut(duration: 0.06) : .spring(response: 0.3, dampingFraction: 0.86)
            return entry.delay(exit)
        }
        return .easeOut(duration: exit)
    }

    func body(content: Content) -> some View {
        content.animation(animation) { page in
            page
                .opacity(isVisible ? 1 : 0)
                // Transform only (no blur): six retained pages stay cheap while hidden.
                .scaleEffect(isVisible || reduceMotion ? 1 : 0.965)
        }
    }
}
