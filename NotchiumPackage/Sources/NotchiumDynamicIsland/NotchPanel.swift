import AppKit

final class NotchPanel: NSPanel {

    override func constrainFrameRect(
        _ frameRect: NSRect,
        to screen: NSScreen?
    ) -> NSRect {
        // Notchium intentionally occupies the menu-bar/notch region.
        // Do not let AppKit push the panel below the menu bar.
        frameRect
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
