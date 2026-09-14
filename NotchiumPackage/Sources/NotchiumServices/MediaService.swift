import Foundation
import NotchiumCore

public enum MediaPlaybackState: String, Sendable { case stopped, paused, playing }
public enum MediaSource: String, CaseIterable, Sendable { case spotify = "Spotify" }
public enum MediaRepeatMode: String, Sendable { case off, context, track }
public enum MediaCommand: Equatable, Sendable {
    case playPause, play, pause, previous, next, seek(TimeInterval), setVolume(Double), toggleShuffle, cycleRepeat
    case setShuffle(Bool), setRepeatMode(MediaRepeatMode)

    public var controlID: String {
        switch self {
        case .playPause, .play, .pause: "playPause"
        case .previous: "previous"
        case .next: "next"
        case .seek: "seek"
        case .toggleShuffle, .setShuffle: "shuffle"
        case .cycleRepeat, .setRepeatMode: "repeat"
        case .setVolume: "volume"
        }
    }
}

public struct MediaCapabilities: Equatable, Sendable {
    public var canPlayPause: Bool
    public var canSkipForward: Bool
    public var canSkipBackward: Bool
    public var canSeek: Bool
    public var canShuffle: Bool
    public var canRepeat: Bool
    public var canReadQueue: Bool
    public init(canPlayPause: Bool = false, canSkipForward: Bool = false,
                canSkipBackward: Bool = false, canSeek: Bool = false,
                canShuffle: Bool = false, canRepeat: Bool = false, canReadQueue: Bool = false) {
        self.canPlayPause = canPlayPause; self.canSkipForward = canSkipForward
        self.canSkipBackward = canSkipBackward; self.canSeek = canSeek
        self.canShuffle = canShuffle; self.canRepeat = canRepeat; self.canReadQueue = canReadQueue
    }
    public func supports(_ command: MediaCommand) -> Bool {
        switch command {
        case .playPause, .play, .pause: canPlayPause
        case .previous: canSkipBackward
        case .next: canSkipForward
        case .seek: canSeek
        case .toggleShuffle, .setShuffle: canShuffle
        case .cycleRepeat, .setRepeatMode: canRepeat
        case .setVolume: false
        }
    }
}

public struct MediaQueueItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public init(id: String, title: String, artist: String) {
        self.id = id; self.title = title; self.artist = artist
    }
}

/// The sole provider snapshot. Artwork is a URL identity; decoded images never enter activity queues.
/// Licensed lyrics can later be supplied by a separate provider keyed by trackID and source.
public struct MediaState: Equatable, Sendable {
    public var availability: FeatureAvailability
    public var playbackState: MediaPlaybackState
    public var trackID: String?
    public var title: String?
    public var artist: String?
    public var artwork: URL?
    public var source: MediaSource?
    public var elapsed: TimeInterval
    public var duration: TimeInterval?
    public var timestamp: Date
    public var playbackRate: Double
    public var capabilities: MediaCapabilities
    public var shuffle: Bool?
    public var repeatMode: MediaRepeatMode?
    public var queue: [MediaQueueItem]?
    public var issue: String?

    public init(availability: FeatureAvailability = .available,
                playbackState: MediaPlaybackState = .stopped, title: String? = nil,
                artist: String? = nil, elapsed: TimeInterval = 0, duration: TimeInterval? = nil,
                trackID: String? = nil, artwork: URL? = nil, source: MediaSource? = nil,
                capabilities: MediaCapabilities = .init(), shuffle: Bool? = nil,
                repeatMode: MediaRepeatMode? = nil, queue: [MediaQueueItem]? = nil, issue: String? = nil,
                timestamp: Date = Date(), playbackRate: Double? = nil) {
        self.availability = availability; self.playbackState = playbackState
        self.title = title; self.artist = artist; self.elapsed = elapsed; self.duration = duration
        self.trackID = trackID; self.artwork = artwork; self.source = source
        self.capabilities = capabilities; self.shuffle = shuffle; self.repeatMode = repeatMode
        self.queue = queue; self.issue = issue
        self.timestamp = timestamp
        self.playbackRate = playbackRate ?? (playbackState == .playing ? 1 : 0)
    }
    public var isPlaying: Bool { playbackState == .playing }
    public var hasMedia: Bool { availability.isUsable && playbackState != .stopped && title != nil }
    public var elapsedTime: TimeInterval {
        guard elapsed.isFinite else { return 0 }
        return min(max(0, elapsed), validDuration ?? max(0, elapsed))
    }
    public var validDuration: TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }
    /// Metadata changes also invalidate a pending seek when a provider reuses its track ID.
    public func isSameTrack(as other: MediaState) -> Bool {
        source == other.source && trackID == other.trackID && title == other.title
            && artist == other.artist && artwork == other.artwork
    }
    public var progress: Double { validDuration.map { elapsedTime / $0 } ?? 0 }
    public var canPlayPause: Bool { hasMedia && capabilities.canPlayPause }
    public var canSkipForward: Bool { hasMedia && capabilities.canSkipForward }
    public var canSkipBackward: Bool { hasMedia && capabilities.canSkipBackward }
    public var canPlay: Bool { canPlayPause && !isPlaying }
    public var canPause: Bool { canPlayPause && isPlaying }
    public var canNext: Bool { canSkipForward }
    public var canPrevious: Bool { canSkipBackward }
    public var canShuffle: Bool { hasMedia && capabilities.canShuffle && shuffle != nil }
    public var canRepeat: Bool { hasMedia && capabilities.canRepeat && repeatMode != nil }
    public var canSeek: Bool { hasMedia && validDuration != nil && capabilities.canSeek }
    /// A bounded, single-line presentation string; views also apply tail truncation to actual width.
    public var collapsedTitle: String {
        let value = (title ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
        return value.count > 120 ? String(value.prefix(119)) + "…" : value
    }
}

public enum MediaFailure: Error, Equatable, LocalizedError, Sendable {
    case unsupported, disconnected, invalidResponse, authorization, keychain, busy, rateLimited(Int)
    public var errorDescription: String? {
        switch self {
        case .unsupported: "This media operation is unavailable."
        case .disconnected: "Connect Spotify in Settings."
        case .invalidResponse: "The media provider could not return playback state."
        case .authorization: "Spotify authorization failed. Connect again."
        case .keychain: "Spotify credentials could not be stored in Keychain."
        case .busy: "A media command is already in progress."
        case .rateLimited(let seconds): "Spotify rate limit reached. Retry in \(seconds) seconds."
        }
    }
}

public protocol MediaProviding: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<MediaState>
    func perform(_ command: MediaCommand) async throws
    func refresh() async
}

public extension MediaProviding {
    func play() async throws { try await perform(.play) }
    func pause() async throws { try await perform(.pause) }
    func togglePlayPause() async throws { try await perform(.playPause) }
    func nextTrack() async throws { try await perform(.next) }
    func previousTrack() async throws { try await perform(.previous) }
    func setShuffle(_ enabled: Bool) async throws { try await perform(.setShuffle(enabled)) }
    func setRepeatMode(_ mode: MediaRepeatMode) async throws { try await perform(.setRepeatMode(mode)) }
    // Passive test adapters may have no external state to refresh.
    func refresh() async {}

    func seek(to position: Double) async throws { try await perform(.seek(position)) }
}

/// Interpolates a real observation; never accumulates timer ticks or mutates provider state.
public func estimatedPlaybackPosition(at now: Date, state: MediaState) -> Double {
    guard let duration = state.validDuration else { return 0 }
    guard state.isPlaying, state.playbackRate.isFinite, state.playbackRate > 0 else {
        return state.elapsedTime
    }
    let delta = now.timeIntervalSince(state.timestamp)
    guard delta.isFinite else { return state.elapsedTime }
    let estimated = state.elapsedTime + delta * state.playbackRate
    return min(max(estimated, 0), duration)
}

// Preserve the Stage 1 names at existing injection sites.
public typealias MediaService = MediaProviding
public typealias MediaSnapshot = MediaState
public typealias RealMediaService = RealMediaProvider
public typealias MockMediaService = MockMediaProvider
