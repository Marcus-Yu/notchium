import AppKit
import SwiftUI

/// A hit-tested view in unused navigation space; never monitors control events.
struct NotchPageSwipeSurface: NSViewRepresentable {
    let model: NotchPageModel
    let isEnabled: Bool
    var reduceMotion = false

    func makeNSView(context: Context) -> SwipeView { SwipeView(model: model) }
    func updateNSView(_ view: SwipeView, context: Context) {
        view.model = model
        view.isEnabled = isEnabled
        view.reduceMotion = reduceMotion
        if !isEnabled { view.session.cancel() }
    }

    final class SwipeView: NSView {
        var model: NotchPageModel
        var isEnabled = false
        var reduceMotion = false
        var session = PageSwipeSession()

        init(model: NotchPageModel) {
            self.model = model
            super.init(frame: .zero)
            toolTip = "Swipe horizontally to change page"
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? {
            isEnabled ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            guard isEnabled, event.hasPreciseScrollingDeltas,
                  event.momentumPhase.isEmpty, !event.phase.isEmpty else { return }
            if event.phase.contains(.cancelled) { session.cancel(); return }
            if event.phase.contains(.began) { session.begin() }
            if let forward = session.update(x: event.scrollingDeltaX, y: event.scrollingDeltaY) {
                withAnimation(reduceMotion ? NotchMotion.reduced : NotchMotion.page) {
                    model.moveSelection(forward: forward)
                }
            }
            if event.phase.contains(.ended) { session.cancel() }
        }
    }
}
