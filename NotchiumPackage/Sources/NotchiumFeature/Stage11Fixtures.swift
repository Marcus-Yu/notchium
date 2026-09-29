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
        let services: ServiceRegistry
        if CommandLine.arguments.contains("--notchium-stability-fixture") {
            let media = MockMediaProvider(snapshot: .init(playbackState: .paused,
                title: "Audit Track", artist: "Fixture", elapsed: 30, duration: 180, trackID: "audit",
                volumePercent: 50, source: .spotify, capabilities: .init(canPlayPause: true, canSkipForward: true,
                    canSkipBackward: true, canSeek: true, canShuffle: true, canRepeat: true,
                    canSetVolume: true)))
            services = .mock(media: media, audioDevices: MockAudioDevicesService(snapshot:
                .init(availability: .available, outputs: [.init(id: "audit", name: "Audit Speakers",
                    isDefaultOutput: true, volume: 0.5, isMuted: false, canSetVolume: true, canSetMute: true)])))
        } else { services = .mock() }
        return NotchiumApplicationController(environment: .mock(clock: ContinuousAppClock(), services: services),
            reminderService: reminders, shortcutService: MockShortcutService(shortcuts: [shortcut]), actionStore: store)
    }
}
#endif
