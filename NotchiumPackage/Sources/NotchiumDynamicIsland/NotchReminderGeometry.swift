import SwiftUI

public enum NotchReminderGeometry {
    public static let height: CGFloat = 70

    public static func width(for layout: NotchPanelLayout) -> CGFloat {
        CollapsedMediaGeometry(
            hardwareWidth: layout.hardwareNotchGeometry?.frame.width ?? 0,
            hardwareHeight: layout.collapsedVisibleFrame.height
        ).width
    }

    public static func contentFrame(for layout: NotchPanelLayout) -> CGRect {
        let width = width(for: layout)
        return CGRect(x: layout.collapsedVisibleFrame.midX - width / 2,
                      y: layout.collapsedVisibleFrame.minY - height,
                      width: width, height: height)
    }
}
