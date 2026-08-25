import Foundation
import NotchCore

public enum MediaPlaybackState: String, Sendable {
    case stopped
    case paused
    case playing
}

public enum MediaCommand: Sendable {
    case playPause
    case previous
    case next
    case seek(TimeInterval)
    case setVolume(Double)
    case toggleShuffle
    case cycleRepeat
}

public struct MediaSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let playbackState: MediaPlaybackState
    public let title: String?
    public let artist: String?
    public let elapsed: TimeInterval
    public let duration: TimeInterval?

    public init(
        availability: FeatureAvailability,
        playbackState: MediaPlaybackState = .stopped,
        title: String? = nil,
        artist: String? = nil,
        elapsed: TimeInterval = 0,
        duration: TimeInterval? = nil
    ) {
        self.availability = availability
        self.playbackState = playbackState
        self.title = title
        self.artist = artist
        self.elapsed = elapsed
        self.duration = duration
    }
}

public protocol MediaService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<MediaSnapshot>
    func perform(_ command: MediaCommand) async throws
}

public struct RealMediaService: MediaService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.media)
    }

    public func updates() async -> AsyncStream<MediaSnapshot> {
        oneShotStream(MediaSnapshot(availability: stageOneUnavailable(.media)))
    }

    public func perform(_ command: MediaCommand) async throws {
        throw ServiceFailure.stageTwoRequired(.media)
    }
}

public struct MockMediaService: MediaService {
    public let snapshot: MediaSnapshot

    public init(snapshot: MediaSnapshot = MediaSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<MediaSnapshot> {
        oneShotStream(snapshot)
    }

    public func perform(_ command: MediaCommand) async throws {}
}
