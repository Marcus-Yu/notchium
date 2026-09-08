import SwiftUI
import NotchiumDynamicIsland

extension MediaFeatureModel: NotchMediaRendering {
    public func collapsedMedia(hardwareWidth: CGFloat) -> AnyView {
        AnyView(CollapsedMediaView(model: self, hardwareWidth: hardwareWidth))
    }
    public func expandedMedia() -> AnyView { AnyView(MediaPageView(model: self)) }
}
