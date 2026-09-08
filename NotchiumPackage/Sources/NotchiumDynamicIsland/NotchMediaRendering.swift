import SwiftUI

/// Content injection keeps services and media feature state outside the frozen shell engine.
@MainActor public protocol NotchMediaRendering: AnyObject {
    func collapsedMedia(hardwareWidth: CGFloat) -> AnyView
    func expandedMedia() -> AnyView
}

extension EnvironmentValues {
    @Entry var notchMediaRenderer: (any NotchMediaRendering)? = nil
}
