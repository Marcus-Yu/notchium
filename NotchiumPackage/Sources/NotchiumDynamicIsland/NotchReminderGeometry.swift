import SwiftUI

public enum NotchReminderGeometry {
    public static let minimumHeight: CGFloat = 44

    public static func width(for layout: NotchPanelLayout) -> CGFloat {
        let mediaWidth = CollapsedMediaGeometry(
            hardwareWidth: layout.hardwareNotchGeometry?.frame.width ?? 0,
            hardwareHeight: layout.collapsedVisibleFrame.height
        ).width
        // A bounded amount of breathing room, independent of the event title.
        return max(mediaWidth, min(380, max(340, mediaWidth + 64)))
    }

    public static func contentFrame(for layout: NotchPanelLayout, height: CGFloat) -> CGRect {
        let width = width(for: layout)
        return CGRect(x: layout.collapsedVisibleFrame.midX - width / 2,
                      y: layout.collapsedVisibleFrame.minY - height,
                      width: width, height: height)
    }
}

/// One reversible reveal: width first, then height. Reversing the same progress
/// collapses height before returning the width, without timers or queued phases.
struct NotchReminderReveal {
    var progress: CGFloat

    var width: CGFloat { fraction(from: 0, to: 0.55) }
    var height: CGFloat { fraction(from: 0.2, to: 1) }

    private func fraction(from start: CGFloat, to end: CGFloat) -> CGFloat {
        let t = min(1, max(0, (progress - start) / (end - start)))
        return t * t * (3 - 2 * t)
    }
}
