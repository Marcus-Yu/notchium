import SwiftUI

/// Content injection for the Shelf page; file access, transfers and screenshots stay in the feature.
@MainActor public protocol NotchShelfRendering: AnyObject {
    func expandedShelf() -> AnyView
    func setPageVisible(_ visible: Bool)
    /// Adds dropped file URLs by reference (never copies). Returns how many were accepted.
    @discardableResult func acceptDroppedFiles(_ urls: [URL]) -> Int
}

/// Interaction state of a system file drag relative to the collapsed notch.
public enum NotchFileDragState: Equatable, Sendable {
    case idle
    /// A file drag is near the notch: the drop affordance is shown.
    case nearby
    /// The pointer is over the drop affordance.
    case targeted
}

extension EnvironmentValues {
    @Entry public var notchShelfPageVisible = false
}
