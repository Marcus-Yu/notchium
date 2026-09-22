import Foundation

/// Hints invalidate a read; they never supply UI metadata or identify the active Connect device.
public struct SpotifyPlaybackEvent: Equatable, Sendable {
    public var trackID: String?
    public var isPlaying: Bool?
    public var position: Double?

    public init(trackID: String? = nil, isPlaying: Bool? = nil, position: Double? = nil) {
        self.trackID = trackID
        self.isPlaying = isPlaying
        self.position = position
    }

    init(userInfo: [AnyHashable: Any]?) {
        let uri = userInfo?["Track ID"] as? String
        trackID = uri.flatMap { $0.hasPrefix("spotify:track:") ? String($0.dropFirst(14)) : nil }
        switch userInfo?["Player State"] as? String {
        case "Playing": isPlaying = true
        case "Paused", "Stopped": isPlaying = false
        default: isPlaying = nil
        }
        let rawPosition = (userInfo?["Playback Position"] as? NSNumber)?.doubleValue
        position = rawPosition.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
}

public protocol SpotifyPlaybackEventProviding: Sendable {
    func events() async -> AsyncStream<SpotifyPlaybackEvent>
}

public struct SpotifyDesktopPlaybackEvents: SpotifyPlaybackEventProviding {
    public init() {}

    @MainActor public func events() async -> AsyncStream<SpotifyPlaybackEvent> {
        Self.observe(center: DistributedNotificationCenter.default())
    }

    /// Injectable NotificationCenter also exercises observer delivery/teardown without Spotify.
    @MainActor static func observe(center: NotificationCenter) -> AsyncStream<SpotifyPlaybackEvent> {
        let pair = AsyncStream<SpotifyPlaybackEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let token = center.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"),
                                       object: nil, queue: .main) { notification in
            pair.continuation.yield(.init(userInfo: notification.userInfo))
        }
        let observation = PlaybackNotificationObservation(center: center, token: token)
        pair.continuation.onTermination = { _ in observation.cancel() }
        return pair.stream
    }
}

// The token and center are immutable. NotificationCenter's observer removal is thread-safe;
// AsyncStream can terminate on any executor. No non-Sendable notification crosses executors.
private final class PlaybackNotificationObservation: @unchecked Sendable {
    let center: NotificationCenter
    let token: any NSObjectProtocol
    init(center: NotificationCenter, token: any NSObjectProtocol) {
        self.center = center
        self.token = token
    }
    func cancel() { center.removeObserver(token) }
    deinit { cancel() }
}
