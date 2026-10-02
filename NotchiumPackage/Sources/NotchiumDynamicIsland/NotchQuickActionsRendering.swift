import SwiftUI
import NotchiumCore

@MainActor public protocol NotchQuickActionsRendering: AnyObject {
    var showsHomeActions: Bool { get }
    func reminderButton() -> AnyView
    func homeActions() -> AnyView
    /// Primary Home regions only; shortcuts are an optional auxiliary strip.
    var homeSections: [HomeSectionID] { get }
}

public extension NotchQuickActionsRendering {
    var homeSections: [HomeSectionID] { [.media, .calendar] }
}

extension EnvironmentValues {
    @Entry public var notchHomePageVisible = false
}
