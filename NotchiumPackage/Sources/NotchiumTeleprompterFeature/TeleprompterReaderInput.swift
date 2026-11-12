import AppKit
import SwiftUI

/// Pointer input for the crawling reader: a click reanchors at the line under the pointer, and
/// a scroll looks ahead or back while not reading. The lines underneath stay ordinary SwiftUI
/// buttons for VoiceOver and UI automation; this view only takes the mouse.
struct TeleprompterReaderInput: NSViewRepresentable {
    let allowsBrowsing: Bool
    let click: @MainActor (CGFloat) -> Void
    let scroll: @MainActor (CGFloat) -> Void

    func makeNSView(context: Context) -> InputView { InputView() }

    func updateNSView(_ view: InputView, context: Context) {
        view.allowsBrowsing = allowsBrowsing
        view.click = click
        view.scroll = scroll
    }

    final class InputView: NSView {
        var allowsBrowsing = false
        var click: (@MainActor (CGFloat) -> Void)?
        var scroll: (@MainActor (CGFloat) -> Void)?

        override init(frame: NSRect) {
            super.init(frame: frame)
            toolTip = "Read from this line"
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) { nil }

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            click?(convert(event.locationInWindow, from: nil).y)
        }

        override func scrollWheel(with event: NSEvent) {
            guard allowsBrowsing else { super.scrollWheel(with: event); return }
            // Trackpads report points; wheels report lines, converted at a typical line height.
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 16
            scroll?(delta)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}
