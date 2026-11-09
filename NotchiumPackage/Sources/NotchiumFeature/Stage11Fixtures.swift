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
        if CommandLine.arguments.contains("--notchium-reminders-unverified") { reminders.authorization = .verificationFailed }
        let services: ServiceRegistry
        let nativeFiles = CommandLine.arguments.contains("--notchium-native-files-fixture")
        let qualityFixture = CommandLine.arguments.contains("--notchium-quality-fixture")
        let nativeFile = URL(fileURLWithPath: "/private/tmp/notchium-stage26-native-files-\(UUID().uuidString).txt")
        if nativeFiles {
            // Explicit disposable UI-test input; never enumerate or modify user folders.
            try? Data("Disposable Notchium sharing acceptance fixture".utf8).write(to: nativeFile, options: .atomic)
            services = .mock()
            (services.shelf as? MockShelfService)?.existingPaths.insert(nativeFile.path)
        } else if CommandLine.arguments.contains("--notchium-system-feedback-fixture") {
            // Explicit hardware qualification: real audio output and key handling, with mock
            // calendar, file, clipboard and provider services. No permission request at launch.
            services = .mock(audioDevices: RealAudioDevicesService())
        } else if qualityFixture {
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
            services = .mock(media: RealMediaProvider(controller: .init(
                executor: SettingsFixtureScriptExecutor(), application: SettingsFixtureSpotifyApplication())))
        } else { services = .mock() }
        let voiceFixture = CommandLine.arguments.contains("--notchium-teleprompter-voice-fixture")
        let declarationOpening = "In Congress, July 4, 1776. The unanimous Declaration of the thirteen united States of America. When in the Course of human events, it becomes necessary for one people to dissolve the political bands which have connected them with another. And to assume among the powers of the earth the separate and equal station to which the Laws of Nature entitle them."
        let fixtureSpeech = MockTeleprompterSpeechService(events: voiceFixture ? [
            .inputDevice(name: "Fixture built-in microphone"), .ready, .audioLevel(0.02),
            .transcript(text: "In Congress, July 4th, 1776, the unanimous declaration of the 13 United States of America", audioStart: 0, audioEnd: 6, isFinal: false)
        ] : [.ready], microphones: voiceFixture ? [
            .init(id: "fixture-built-in", name: "Fixture built-in microphone", isDefault: true),
            .init(id: "fixture-headset", name: "Fixture headset", isDefault: false)
        ] : [])
        let scriptStore = MockTeleprompterScriptStore(scripts: voiceFixture ? [
            .init(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
                  title: "Declaration voice fixture", text: declarationOpening)
        ] : [])
        let controller = NotchiumApplicationController(environment: .mock(clock: ContinuousAppClock(), services: services,
            featureFlags: qualityFixture ? .stageNineteenUtilities : .stageFifteenFiles),
            reminderService: reminders, shortcutService: MockShortcutService(shortcuts: [shortcut]), actionStore: store,
            teleprompterSpeech: fixtureSpeech, teleprompterStore: scriptStore)
        if nativeFiles { controller.filesModel.shelf.add([nativeFile]) }
        return controller
    }
}

/// Settings controls remain real while all OS integration is replaced.
private struct SettingsFixtureScriptExecutor: SpotifyScriptExecuting {
    func permission() async -> SpotifyAutomationPermission { .notDetermined }
    func execute(_ source: String) async throws -> [String] { throw MediaFailure.unsupported }
}
private struct SettingsFixtureSpotifyApplication: SpotifyApplicationLaunching {
    func isSpotifyInstalled() async -> Bool { true }
    func isSpotifyRunning() async -> Bool { true }
    func launchSpotify() async throws {}
}
#endif
