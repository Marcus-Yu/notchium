import SwiftUI
import NotchiumDynamicIsland

extension MediaFeatureModel: NotchMediaRendering {
    public func homeMedia(openMusic: @escaping @MainActor () -> Void) -> AnyView {
        AnyView(HomeMediaView(model: self, openMusic: openMusic))
    }
    public func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView {
        AnyView(CollapsedMediaView(model: self, hardwareWidth: hardwareWidth, hardwareHeight: hardwareHeight))
    }
    public func mediaArtwork(size: CGFloat) -> AnyView { AnyView(MediaArtwork(url: state.artwork, size: size)) }
    public func expandedMedia() -> AnyView { AnyView(MediaPageView(model: self)) }
}
