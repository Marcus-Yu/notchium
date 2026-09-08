import Foundation
import NotchiumCore

public enum MediaPlaybackState: String, Sendable { case stopped, paused, playing }
public enum MediaSource: String, CaseIterable, Sendable { case appleMusic = "Apple Music", spotify = "Spotify" }
public enum MediaRepeatMode: String, Sendable { case off, context, track }
public enum MediaCommand: Equatable, Sendable {
    case playPause, previous, next, seek(TimeInterval), setVolume(Double), toggleShuffle, cycleRepeat
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
        case .playPause: canPlayPause
        case .previous: canSkipBackward
        case .next: canSkipForward
        case .seek: canSeek
        case .toggleShuffle: canShuffle
        case .cycleRepeat: canRepeat
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
                repeatMode: MediaRepeatMode? = nil, queue: [MediaQueueItem]? = nil, issue: String? = nil) {
        self.availability = availability; self.playbackState = playbackState
        self.title = title; self.artist = artist; self.elapsed = elapsed; self.duration = duration
        self.trackID = trackID; self.artwork = artwork; self.source = source
        self.capabilities = capabilities; self.shuffle = shuffle; self.repeatMode = repeatMode
        self.queue = queue; self.issue = issue
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
    public var progress: Double { validDuration.map { elapsedTime / $0 } ?? 0 }
    public var canPlayPause: Bool { hasMedia && capabilities.canPlayPause }
    public var canSkipForward: Bool { hasMedia && capabilities.canSkipForward }
    public var canSkipBackward: Bool { hasMedia && capabilities.canSkipBackward }
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
}

// Preserve the Stage 1 names at existing injection sites.
public typealias MediaService = MediaProviding
public typealias MediaSnapshot = MediaState
public typealias RealMediaService = RealMediaProvider
public typealias MockMediaService = MockMediaProvider
