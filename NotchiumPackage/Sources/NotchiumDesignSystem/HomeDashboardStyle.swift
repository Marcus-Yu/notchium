import SwiftUI

/// Interior Home metrics; every page retains the same expanded shell dimensions.
public enum HomeDashboardStyle {
    public static let mediaFraction: CGFloat = 0.56
    public static let shortcutHeight: CGFloat = 34
    public static let shortcutWidth: CGFloat = 110
    public static let shortcutGap: CGFloat = 6
    public static let focusInset: CGFloat = 2
    public static let dividerHeight: CGFloat = 1
    public static let shortcutStripHeight = shortcutHeight + focusInset * 2
    public static let shortcutRegionHeight = shortcutStripHeight + ExpandedPageStyle.Space.xs * 2 + dividerHeight
}

public extension EnvironmentValues {
    /// Presentation only: compact primary regions when Home also contains shortcuts.
    @Entry var homeUsesCompactLayout = false
}
