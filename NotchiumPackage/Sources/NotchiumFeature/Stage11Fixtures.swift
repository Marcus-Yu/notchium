#if DEBUG
import Foundation
import NotchiumCore
import NotchiumPersistence
import NotchiumServices

extension NotchiumApplicationController {
    /// Explicit UI-test launch only: never requests EventKit access or runs a user's shortcuts.
    static func stage11Fixture() -> NotchiumApplicationController {
        let preferences = UserDefaults(suiteName: "Notchium.Stage11.UITests")!
        preferences.removePersistentDomain(forName: "Notchium.Stage11.UITests")
        let store = QuickActionStore(preferences: preferences)
        let shortcut = ExistingShortcut(id: UUID(), name: "Review notes")
        try? store.save(QuickAction(kind: .shortcut, displayName: shortcut.name, target: shortcut.name,
                                   shortcutID: shortcut.id, pinnedToHome: true))
        for (name, symbol) in [("Work", "globe"), ("Projects", "folder"), ("Reading", "bookmark")] {
            try? store.save(QuickAction(kind: .url, displayName: name, target: "https://example.com",
                                       symbol: symbol, pinnedToHome: true))
        }
        store.showOnHome = true
        let reminders = MockReminderService()
        if CommandLine.arguments.contains("--notchium-reminders-denied") { reminders.authorization = .denied }
        return NotchiumApplicationController(environment: .mock(clock: ContinuousAppClock()),
            reminderService: reminders, shortcutService: MockShortcutService(shortcuts: [shortcut]), actionStore: store)
    }
}
#endif
