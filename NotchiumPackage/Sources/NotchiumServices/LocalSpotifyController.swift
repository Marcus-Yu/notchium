import AppKit
import Foundation
import NotchiumCore

public protocol SpotifyApplicationLaunching: Sendable {
    func isSpotifyInstalled() async -> Bool
    func isSpotifyRunning() async -> Bool
    func launchSpotify() async throws
}

public struct SystemSpotifyApplicationLauncher: SpotifyApplicationLaunching {
    public init() {}
    @MainActor public func isSpotifyInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
    }
    public func isSpotifyRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }
    @MainActor public func launchSpotify() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            throw MediaFailure.spotifyUnavailable
        }
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    public static var localDeviceNames: Set<String> {
        Set(["this mac", ProcessInfo.processInfo.hostName.lowercased(),
             Host.current().localizedName?.lowercased()].compactMap { $0 })
    }
}

public protocol SpotifyLocalPreferencesStoring: Sendable {
    func isEnabled() async -> Bool
    func setEnabled(_ enabled: Bool) async
}

public actor SpotifyLocalPreferences: SpotifyLocalPreferencesStoring {
    private let defaults: UserDefaults
    public init() { defaults = .standard }
    public func isEnabled() -> Bool { defaults.bool(forKey: "SpotifyLocalControlEnabled") }
    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "SpotifyLocalControlEnabled")
        // The old client ID is not a secret. Legacy Keychain credentials are left untouched:
        // local playback never reads them, and upgrades cannot affect unrelated saved keys.
        defaults.removeObject(forKey: "SpotifyClientID")
    }
}

/// Stateless adapter: provider snapshots and reconciliation remain owned by RealMediaProvider.
public struct LocalSpotifyController: Sendable {
    public static let deviceID = "spotify-local-mac"
    public static let queueUnavailable = "Spotify doesn’t share its queue with local controls."
    private let executor: any SpotifyScriptExecuting
    private let application: any SpotifyApplicationLaunching
    private let preferences: any SpotifyLocalPreferencesStoring

    public init(executor: any SpotifyScriptExecuting = SystemSpotifyScriptExecutor(),
                application: any SpotifyApplicationLaunching = SystemSpotifyApplicationLauncher(),
                preferences: any SpotifyLocalPreferencesStoring = SpotifyLocalPreferences()) {
        self.executor = executor; self.application = application; self.preferences = preferences
    }

    public func read(prompt: Bool = false) async throws -> MediaState {
        try Task.checkCancellation()
        guard await application.isSpotifyInstalled() else { return Self.empty(.notInstalled) }
        guard await application.isSpotifyRunning() else { return Self.empty(.notRunning) }
        if prompt { await preferences.setEnabled(true) }
        guard await preferences.isEnabled() else { return Self.empty(.needsPermission) }
        try Task.checkCancellation()
        switch await executor.permission() {
        case .notDetermined:
            guard prompt else { return Self.empty(.needsPermission) }
        case .denied: return Self.empty(.denied)
        case .unavailable: throw MediaFailure.spotifyUnavailable
        case .allowed: break
        }
        try Task.checkCancellation()
        // A normal protected Apple Event triggers the system dialog. The permission API is
        // used only for nonprompting checks; its prompting form can stall before showing UI.
        if prompt { await MainActor.run { NSApp.activate() } }
        do {
            let fields = try await executor.execute(Self.snapshotScript)
            try Task.checkCancellation()
            return try Self.decode(fields)
        } catch let error as SpotifyScriptFailure {
            if error.code == -1743 { return Self.empty(.denied) }
            if error.code == -600 || error.code == -609 { return Self.empty(.notRunning) }
            throw error
        }
    }

    public func disable() async { await preferences.setEnabled(false) }
    public func openSpotify() async throws { try await application.launchSpotify() }

    public func perform(_ command: MediaCommand, state: MediaState) async throws {
        guard await application.isSpotifyRunning() else { throw MediaFailure.spotifyUnavailable }
        guard await preferences.isEnabled(), await executor.permission() == .allowed else {
            throw MediaFailure.authorization
        }
        let script = try Self.commandScript(command, state: state)
        try Task.checkCancellation()
        _ = try await executor.execute(script)
        try Task.checkCancellation()
    }

    static func empty(_ status: LocalSpotifyStatus) -> MediaState {
        let denied = status == .denied
        let needsPermission = status == .needsPermission
        return .init(availability: denied ? .unavailable(.permissionDenied) :
                        needsPermission ? .unavailable(.permissionNotDetermined) : .available,
                     connectionState: denied ? .error : needsPermission ? .unauthenticated : .authenticated,
                     source: .spotify, queueIssue: queueUnavailable, issue: status == .ready ? nil : status.message,
                     localSpotifyStatus: status)
    }

    /// A typed AppleScript list avoids delimiter/escaping bugs in arbitrary track metadata.
    static func decode(_ fields: [String]) throws -> MediaState {
        guard let status = fields.first else { throw MediaFailure.invalidResponse }
        if status == "notRunning" { return empty(.notRunning) }
        if status == "stopped" { return empty(.ready) }
        guard fields.count == 14, let playback = MediaPlaybackState(rawValue: status),
              playback != .stopped, let milliseconds = Double(fields[6]), milliseconds.isFinite,
              milliseconds > 0, let position = Double(fields[7]), position.isFinite,
              let volume = Int(fields[8]), !fields[2].isEmpty else { throw MediaFailure.invalidResponse }
        let artwork = URL(string: fields[5]).flatMap { $0.scheme == "https" && $0.host == "i.scdn.co" ? $0 : nil }
        return .init(playbackState: playback, title: fields[2], artist: fields[3], album: fields[4],
                     elapsed: min(max(0, position), milliseconds / 1000), duration: milliseconds / 1000,
                     trackID: fields[1].hasPrefix("spotify:track:") ? String(fields[1].dropFirst(14)) : fields[1],
                     activeDeviceID: deviceID, activeDeviceName: "This Mac", activeDeviceType: "Computer",
                     volumePercent: min(max(volume, 0), 100), artwork: artwork, source: .spotify,
                     capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true,
                                         canSeek: true, canShuffle: fields[11] == "true", canRepeat: fields[12] == "true",
                                         canReadQueue: false, canSetVolume: true),
                     shuffle: fields[9] == "true", repeatMode: fields[10] == "true" ? .context : .off,
                     queueIssue: queueUnavailable, localSpotifyStatus: .ready)
    }

    static func commandScript(_ command: MediaCommand, state: MediaState) throws -> String {
        guard state.capabilities.supports(command) else { throw MediaFailure.unsupported }
        let action: String
        switch command {
        case .playPause: action = "playpause"
        case .play: action = "play"
        case .pause: action = "pause"
        case .previous: action = "previous track"
        case .next: action = "next track"
        case .seek(let seconds):
            guard seconds.isFinite, let duration = state.validDuration else { throw MediaFailure.unsupported }
            // Setting player position preserves Spotify's current playback state; never issue play.
            action = "set player position to \(min(max(seconds, 0), duration))"
        case .setVolume(let value):
            guard value.isFinite else { throw MediaFailure.unsupported }
            action = "set sound volume to \(Int((min(max(value, 0), 1) * 100).rounded()))"
        case .setShuffle(let enabled): action = "set shuffling to \(enabled)"
        case .toggleShuffle: action = "set shuffling to not shuffling"
        case .setRepeatMode(.track): throw MediaFailure.unsupported
        case .setRepeatMode(let mode): action = "set repeating to \(mode != .off)"
        case .cycleRepeat: action = "set repeating to not repeating"
        }
        return """
        if application id "com.spotify.client" is not running then error number -600
        with timeout of 5 seconds
            tell application id "com.spotify.client"
                \(action)
            end tell
        end timeout
        return {"ok"}
        """
    }

    static let snapshotScript = """
    if application id "com.spotify.client" is not running then return {"notRunning"}
    with timeout of 5 seconds
        tell application id "com.spotify.client"
            repeat 2 times
                set playback to player state as text
                if playback is "stopped" then return {"stopped"}
                set song to current track
                set songID to id of song
                set songTitle to name of song
                set songArtist to artist of song
                set songAlbum to album of song
                set songArtwork to artwork url of song
                set songDuration to duration of song
                set songPosition to player position
                set songVolume to sound volume
                set songShuffle to shuffling
                set songRepeat to repeating
                set allowsShuffle to shuffling enabled
                set allowsRepeat to repeating enabled
                if songID is (id of current track) and playback is (player state as text) then
                    return {playback, songID, songTitle, songArtist, songAlbum, songArtwork, songDuration, songPosition, songVolume, songShuffle, songRepeat, allowsShuffle, allowsRepeat, "local"}
                end if
            end repeat
        end tell
    end timeout
    error number -1728
    """
}
