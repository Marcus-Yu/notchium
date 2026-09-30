import SwiftUI

/// Shared dimensions for drawing and pointer retention; neither depends on content updates.
public enum NotchNotificationGeometry {
    static let calendarHeight: CGFloat = 88
    static let audioHeight: CGFloat = 56
    static let lowerRadius: CGFloat = 34
    static let shoulderRadius: CGFloat = 12
    /// Horizontal safe margin for every downward notification's content. The banner's body
    /// wall sits a shoulder's width inside its frame, and the lower corners curve in further.
    public static let contentHorizontalInset: CGFloat = shoulderRadius + 20
    /// Text starts further in than trailing controls: it sits beside the lower-left curve.
    public static let contentLeadingInset: CGFloat = shoulderRadius + 36

    static func contentHeight(for style: NotchNotification.PresentationStyle) -> CGFloat {
        switch style {
        case .calendar: calendarHeight
        case .compact: 0
        case .feedback: audioHeight
        }
    }

    static func size(for style: NotchNotification.PresentationStyle, layout: NotchPanelLayout) -> CGSize {
        if style == .compact {
            // Interaction covers the body only; the shoulders are a visual flare.
            return CGSize(width: NotchCompactGeometry(layout: layout).bodyWidth, height: layout.collapsedVisibleFrame.height)
        }
        let mediaWidth = CollapsedMediaGeometry(hardwareWidth: layout.hardwareNotchGeometry?.frame.width ?? 0,
                                               hardwareHeight: layout.collapsedVisibleFrame.height).width
        return CGSize(width: style == .calendar ? NotchReminderGeometry.width(for: layout) : max(292, mediaWidth, layout.collapsedVisibleFrame.width),
               height: layout.collapsedVisibleFrame.height + contentHeight(for: style))
    }

    static func frame(for style: NotchNotification.PresentationStyle, layout: NotchPanelLayout) -> CGRect {
        let size = size(for: style, layout: layout)
        return CGRect(x: layout.collapsedVisibleFrame.midX - size.width / 2,
                      y: layout.collapsedVisibleFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    static func interactionFrame(for style: NotchNotification.PresentationStyle,
                                 layout: NotchPanelLayout, expanded: Bool) -> CGRect {
        guard expanded else { return frame(for: style, layout: layout) }
        return CGRect(x: layout.panelFrame.midX - layout.expandedSize.width / 2,
                      y: layout.panelFrame.maxY - layout.expandedSize.height,
                      width: layout.expandedSize.width, height: contentHeight(for: style))
    }
}
