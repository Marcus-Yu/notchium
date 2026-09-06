import AppKit
import SwiftUI

// Horizontal trackpad scrolling avoids consuming Stage 2's click-to-pin gesture.
struct NotchPageSwipeSurface: NSViewRepresentable {
    let model: NotchPageModel

    func makeNSView(context: Context) -> SwipeView { SwipeView(model: model) }
    func updateNSView(_ nsView: SwipeView, context: Context) { nsView.model = model }

    final class SwipeView: NSView {
        var model: NotchPageModel
        private var horizontalDistance: CGFloat = 0
        private var switched = false

        init(model: NotchPageModel) {
            self.model = model
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func scrollWheel(with event: NSEvent) {
            if event.phase.contains(.began) {
                horizontalDistance = 0
                switched = false
            }
            guard event.momentumPhase.isEmpty else { return }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
            horizontalDistance += event.scrollingDeltaX
            if !switched, abs(horizontalDistance) >= 30 {
                model.moveSelection(forward: horizontalDistance < 0)
                switched = true
            }
            if event.phase.isEmpty || event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                horizontalDistance = 0
                switched = false
            }
        }
    }
}
