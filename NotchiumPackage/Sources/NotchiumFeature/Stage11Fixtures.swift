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
        let qualityFixture = CommandLine.arguments.contains("--notchium-quality-fixture")
        if qualityFixture {
            services = qualityServices()
        } else if CommandLine.arguments.contains("--notchium-stability-fixture") {
            let media = MockMediaProvider(snapshot: .init(playbackState: .paused,
                title: "Audit Track", artist: "Fixture", elapsed: 30, duration: 180, trackID: "audit",
                volumePercent: 50, source: .spotify, capabilities: .init(canPlayPause: true, canSkipForward: true,
                    canSkipBackward: true, canSeek: true, canShuffle: true, canRepeat: true,
                    canSetVolume: true)))
            services = .mock(media: media, audioDevices: MockAudioDevicesService(snapshot:
                .init(availability: .available, outputs: [.init(id: "audit", name: "Audit Speakers",
                    isDefaultOutput: true, volume: 0.5, isMuted: false, canSetVolume: true, canSetMute: true)])))
        } else if CommandLine.arguments.contains("--notchium-media-settings-fixture") {
            let transport = SettingsFixtureTransport()
            let authorization = SpotifyAuthorization(store: SettingsFixtureTokenStore(), transport: transport)
            services = .mock(media: RealMediaProvider(authorization: authorization, transport: transport))
        } else { services = .mock() }
        return NotchiumApplicationController(environment: .mock(clock: ContinuousAppClock(), services: services,
            featureFlags: qualityFixture ? .stageNineteenUtilities : .stageFifteenFiles),
            reminderService: reminders, shortcutService: MockShortcutService(shortcuts: [shortcut]), actionStore: store)
    }
}

/// Settings UI tests retain the real connection controls without reading user credentials
/// or making network requests. Authorization writes fail rather than pretending to save.
private struct SettingsFixtureTokenStore: SpotifyTokenStoring {
    func read() throws -> Data? { nil }
    func write(_ data: Data) throws { throw MediaFailure.keychain }
    func remove() throws {}
}

private struct SettingsFixtureTransport: MediaHTTPTransport {
    func send(_ request: URLRequest) async throws -> MediaHTTPResponse { .init(status: 503) }
}
#endif
