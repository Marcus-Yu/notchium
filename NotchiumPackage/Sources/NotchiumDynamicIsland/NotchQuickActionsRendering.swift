import SwiftUI

@MainActor public protocol NotchQuickActionsRendering: AnyObject {
    var showsHomeActions: Bool { get }
    func reminderButton() -> AnyView
    func homeActions() -> AnyView
}
