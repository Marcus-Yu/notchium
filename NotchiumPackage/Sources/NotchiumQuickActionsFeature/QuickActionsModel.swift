import SwiftUI
import Observation
import NotchiumDynamicIsland
import NotchiumPersistence

@MainActor @Observable public final class QuickActionsModel: NotchQuickActionsRendering {
    public var requestedEditID: UUID?
    public let store: QuickActionStore
    public let runner: QuickActionRunner
    public let reminder: QuickReminderModel
    public init(store: QuickActionStore, runner: QuickActionRunner, reminder: QuickReminderModel) {
        self.store = store; self.runner = runner; self.reminder = reminder
    }
    public var showsHomeActions: Bool { store.showOnHome && !store.pinned.isEmpty }
    public func reminderButton() -> AnyView { AnyView(QuickReminderButton(model: reminder)) }
    public func homeActions() -> AnyView { AnyView(HomeQuickActionsView(model: self)) }
}
