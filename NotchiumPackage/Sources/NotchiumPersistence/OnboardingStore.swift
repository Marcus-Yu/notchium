import Foundation
import NotchiumCore

@MainActor public protocol OnboardingStoring {
    func load() throws -> OnboardingState?
    func save(_ state: OnboardingState) throws
    func hasLegacyConfiguration() -> Bool
}

/// A small, atomic app-owned record. No access to Clipboard payloads or Keychain keys.
@MainActor public final class OnboardingStore: OnboardingStoring {
    private let url: URL
    private let preferences: UserDefaults
    private let supportDirectory: URL

    public init(preferences: UserDefaults = .standard, supportDirectory: URL? = nil) {
        self.preferences = preferences
        self.supportDirectory = supportDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchium", isDirectory: true)
        url = self.supportDirectory.appendingPathComponent("Onboarding.json")
    }

    public func load() throws -> OnboardingState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(OnboardingState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: OnboardingState) throws {
        let data = try JSONEncoder().encode(state)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    public func hasLegacyConfiguration() -> Bool {
        // Only genuine app-owned settings count; AppKit/global defaults do not.
        let keys = preferences.dictionaryRepresentation().keys
        if keys.contains(where: {
            $0.hasPrefix("notchium.") || $0.hasPrefix("quickActions.") || $0.hasPrefix("shelf.")
                || $0 == "home.configuration.v1" || $0 == "SpotifyLocalControlEnabled"
                || $0 == "SpotifyClientID" || $0.hasPrefix("waveform.")
                || $0.hasPrefix("audio.") || $0.hasPrefix("media.waveform.")
        }) { return true }
        // Existence checks only: never decrypt history or touch the encryption key to migrate.
        return ["FocusTimer.json", "Clipboard"].contains {
            FileManager.default.fileExists(atPath: supportDirectory.appendingPathComponent($0).path)
        }
    }
}

@MainActor public final class InMemoryOnboardingStore: OnboardingStoring {
    public var state: OnboardingState?
    public var legacy = false
    public init(state: OnboardingState? = nil) { self.state = state }
    public func load() -> OnboardingState? { state }
    public func save(_ state: OnboardingState) { self.state = state }
    public func hasLegacyConfiguration() -> Bool { legacy }
}
