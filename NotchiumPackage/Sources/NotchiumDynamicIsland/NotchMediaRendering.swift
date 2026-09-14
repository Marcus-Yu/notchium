import SwiftUI

/// Content injection keeps services and media feature state outside the frozen shell engine.
@MainActor public protocol NotchMediaRendering: AnyObject {
    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView
    func expandedMedia() -> AnyView
    func mediaArtwork(size: CGFloat) -> AnyView
}

extension EnvironmentValues {
    @Entry public var notchMediaExpanded = true
    @Entry public var notchSharedMediaArtwork = false
    @Entry var notchMediaRenderer: (any NotchMediaRendering)? = nil
}

/// Both media layouts nominate a slot; the shell retains one artwork view while it moves/resizes.
public struct MediaArtworkAnchorKey: PreferenceKey {
    public static var defaultValue: Anchor<CGRect>? { nil }
    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

public struct CollapsedMediaGeometry: Equatable {
    public let hardwareWidth: CGFloat
    public let height: CGFloat
    public let leadingWidth: CGFloat
    public let trailingWidth: CGFloat
    public var width: CGFloat { leadingWidth + hardwareWidth + trailingWidth }
    public var artworkSize: CGFloat { max(0, height - 12) }
    public init(hardwareWidth: CGFloat, hardwareHeight: CGFloat) {
        self.hardwareWidth = hardwareWidth
        height = hardwareHeight
        // Equal flank allocations keep the camera exactly centered, including its blank right gutter.
        leadingWidth = max(0, min(100, (380 - hardwareWidth) / 2))
        trailingWidth = leadingWidth
    }
}
