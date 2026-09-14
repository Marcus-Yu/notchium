import Foundation
import NotchiumCore

public enum MediaFixture: String, CaseIterable, Sendable {
    case play = "Play Mock Song", pause = "Pause", resume = "Resume"
    case next = "Next Track", previous = "Previous Track", longTitle = "Long Song Title"
    case noArtwork = "No Artwork", spotify = "Spotify"
    case queue = "Queue", stop = "Stop Media"
}

public actor MockMediaProvider: MediaProviding {
    public private(set) var snapshot: MediaState
    public private(set) var commands: [MediaCommand] = []
    private var subscribers: [UUID: AsyncStream<MediaState>.Continuation] = [:]
    public private(set) var refreshCount = 0
    public func refresh() { refreshCount += 1; publish(snapshot) }
    private var trackIndex = 0
    private static let tracks: [MediaQueueItem] = [
        .init(id: "midnight", title: "Midnight City", artist: "M83"),
        .init(id: "awake", title: "Awake", artist: "Tycho"),
        .init(id: "intro", title: "Intro", artist: "The xx")
    ]
    public init(snapshot: MediaState = .init()) { self.snapshot = snapshot }
    public func availability() -> FeatureAvailability { snapshot.availability }
    public func updates() -> AsyncStream<MediaState> {
        let id = UUID()
        let pair = AsyncStream<MediaState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = pair.continuation
        pair.continuation.yield(snapshot)
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        return pair.stream
    }
    private func remove(_ id: UUID) { subscribers.removeValue(forKey: id) }
    public func publish(_ state: MediaState) {
        snapshot = state
        for continuation in subscribers.values { continuation.yield(state) }
    }
    public func perform(_ command: MediaCommand) throws {
        guard snapshot.hasMedia, snapshot.capabilities.supports(command) else { throw MediaFailure.unsupported }
        commands.append(command)
        if commands.count > 32 { commands.removeFirst() }
        rebasePosition()
        switch command {
        case .play: snapshot.playbackState = .playing
        case .pause: snapshot.playbackState = .paused
        case .setShuffle(let enabled): snapshot.shuffle = enabled
        case .setRepeatMode(let mode): snapshot.repeatMode = mode
        case .playPause: snapshot.playbackState = snapshot.isPlaying ? .paused : .playing
        case .next: loadTrack(offset: 1); snapshot.elapsed = 0
        case .previous: loadTrack(offset: -1); snapshot.elapsed = 0
        case .seek(let time):
            guard time.isFinite, let duration = snapshot.validDuration else { throw MediaFailure.unsupported }
            snapshot.elapsed = min(max(0, time), duration)
        case .toggleShuffle: snapshot.shuffle = !(snapshot.shuffle ?? false)
        case .cycleRepeat:
            snapshot.repeatMode = snapshot.repeatMode == .off ? .context : snapshot.repeatMode == .context ? .track : .off
        case .setVolume: throw MediaFailure.unsupported
        }
        snapshot.playbackRate = snapshot.isPlaying ? 1 : 0
        publish(snapshot)
    }
    public func apply(_ fixture: MediaFixture) throws {
        rebasePosition()
        switch fixture {
        case .play: loadTrack(offset: 0)
        case .pause: if snapshot.hasMedia { snapshot.playbackState = .paused }
        case .resume: if snapshot.hasMedia { snapshot.playbackState = .playing }
        case .next: try perform(.next); return
        case .previous: try perform(.previous); return
        case .longTitle:
            loadTrack(offset: 0)
            snapshot.title = "A Walk Through the City at Midnight — " + String(repeating: "The Extended Live Session ", count: 8)
        case .noArtwork: loadTrack(offset: 0); snapshot.artwork = nil
        case .spotify: loadTrack(offset: 0); snapshot.source = .spotify
        case .queue:
            if !snapshot.hasMedia { loadTrack(offset: 0) }
            snapshot.queue = Array(Self.tracks.dropFirst()); snapshot.capabilities.canReadQueue = true
        case .stop: snapshot = .init()
        }
        snapshot.playbackRate = snapshot.isPlaying ? 1 : 0
        publish(snapshot)
    }
    private func rebasePosition() {
        let now = Date()
        snapshot.elapsed = estimatedPlaybackPosition(at: now, state: snapshot)
        snapshot.timestamp = now
    }
    private func loadTrack(offset: Int) {
        trackIndex = (trackIndex + offset + Self.tracks.count) % Self.tracks.count
        let track = Self.tracks[trackIndex]
        snapshot = MediaState(playbackState: .playing, title: track.title, artist: track.artist,
                              elapsed: 48, duration: 244, trackID: track.id,
                              artwork: URL(string: "notchium-fixture://artwork/\(track.id)"),
                              source: snapshot.source ?? .spotify,
                              capabilities: .init(canPlayPause: true, canSkipForward: true,
                                                  canSkipBackward: true, canSeek: true,
                                                  canShuffle: true, canRepeat: true, canReadQueue: true),
                              shuffle: false, repeatMode: .off)
    }
}
