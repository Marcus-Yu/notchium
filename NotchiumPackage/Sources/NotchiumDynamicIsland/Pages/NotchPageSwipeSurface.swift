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
        // AppKit monitor token is installed on main and only released at teardown.
        nonisolated(unsafe) private var scrollMonitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor); self.scrollMonitor = nil }
            guard window != nil else { return }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.scrollWheel(with: event)
                return event
            }
        }

        deinit { if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) } }


        init(model: NotchPageModel) {
            self.model = model
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func scrollWheel(with event: NSEvent) {
            // A retiring navigation surface may still receive a queued event during a page transition.
            guard model.selectedPage != .home else {
                horizontalDistance = 0
                switched = false
                return
            }
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
