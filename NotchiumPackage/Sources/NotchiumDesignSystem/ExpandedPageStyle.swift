import SwiftUI

/// Interior rhythm only; the outer notch geometry remains owned by DynamicIsland.
public enum ExpandedPageStyle {
    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
    }
    public static let outerInset: CGFloat = 30
    public static let topInset = Space.sm
    public static let bottomInset = Space.md
    public static let groupGap = Space.md
    public static let columnGap = Space.xl
    public static let controlGap = Space.sm
    public static let headerHeight: CGFloat = 32
    public static let headerControlSize: CGFloat = 28
    public static let controlSize: CGFloat = 32
    public static let compactControlSize: CGFloat = 24
    public static let controlRadius: CGFloat = 6
    public static let selectionRadius: CGFloat = 8
    public static let title: Font = .system(size: 16, weight: .semibold)
    public static let body: Font = .system(size: 12)
    public static let caption: Font = .system(size: 11)
    public static let sectionTitle: Font = .system(size: 11, weight: .medium)
    public static let secondary = Color.white.opacity(0.65)
}
