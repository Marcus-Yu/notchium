import Foundation

/// A short-lived read expectation, shared by commands and external Spotify events.
/// It cannot stop polling and expires independently of the timestamps returned by Spotify.
struct PlaybackReconciliation: Sendable {
    enum Target: Sendable {
        case trackChange
        case position(Double)
        case playingPosition(Double)
        case playing(Bool)
        case device(String)
        case event(SpotifyPlaybackEvent)
    }
    let origin: MediaState
    let target: Target
    let startedAt: TimeInterval
    static let lifetime: TimeInterval = 10

    init?(command: MediaCommand, origin: MediaState, uptime: TimeInterval) {
        let target: Target
        switch command {
        case .next, .previous: target = .trackChange
        case .seek(let position): target = .position(min(max(0, position), origin.validDuration ?? position))
        case .play: target = .playing(true)
        case .pause: target = .playing(false)
        case .playPause: target = .playing(!origin.isPlaying)
        default: return nil
        }
        self.init(origin: origin, target: target, startedAt: uptime)
    }

    init(origin: MediaState, target: Target, startedAt: TimeInterval) {
        self.origin = origin
        self.target = target
        self.startedAt = startedAt
    }

    /// Seek expectations outlive the retry budget: Spotify can report the old progress for seconds.
    var holdsPosition: Bool {
        switch target {
        case .position, .playingPosition: true
        default: false
        }
    }

    /// Desktop hints must not weaken an unfinished seek into a hint that accepts stale progress.
    /// Only a same-track hint reporting a different position (an external seek) replaces a plain seek.
    func preservesSeek(through event: SpotifyPlaybackEvent, uptime: TimeInterval) -> Bool {
        let elapsed = uptime - startedAt
        guard elapsed < Self.lifetime else { return false }
        let position: Double
        switch target {
        case .position(let value), .playingPosition(let value): position = value
        default: return false
        }
        guard event.trackID == nil || event.trackID == origin.trackID else { return false }
        // Seek-then-resume also passes through intermediate paused/old-position hints.
        if case .playingPosition = target { return true }
        guard let reported = event.position else { return true }
        return reported >= max(0, position - 2) && reported <= position + max(0, elapsed) + 2
    }

    func accepts(_ value: MediaState, uptime: TimeInterval) -> Bool {
        let elapsed = max(0, uptime - startedAt)
        if elapsed >= Self.lifetime { return true }
        let changedTrack: Bool
        if let originalID = origin.trackID, let newID = value.trackID {
            changedTrack = originalID != newID
        } else {
            changedTrack = !value.isSameTrack(as: origin)
        }
        switch target {
        case .trackChange:
            return value.hasMedia && changedTrack
        case .position(let position), .playingPosition(let position):
            guard value.hasMedia else { return false }
            if changedTrack { return true }
            if case .playingPosition = target, !value.isPlaying { return false }
            // Execution may lag the click: accept the interval since the requested baseline.
            return value.elapsedTime >= max(0, position - 2)
                && value.elapsedTime <= position + elapsed + 2
        case .playing(let playing):
            return value.hasMedia && value.isPlaying == playing
        case .device(let id):
            return value.activeDeviceID == id
        case .event(let hint):
            if let id = hint.trackID, value.trackID != id { return false }
            if let playing = hint.isPlaying, value.isPlaying != playing { return false }
            if let position = hint.position {
                return value.elapsedTime >= max(0, position - 2)
                    && value.elapsedTime <= position + elapsed + 2
            }
            if hint.trackID != nil || hint.isPlaying != nil { return true }
            return changedTrack || value.playbackState != origin.playbackState
                || value.activeDeviceID != origin.activeDeviceID
                || abs(value.elapsedTime - estimatedPlaybackPosition(at: value.timestamp, state: origin)) > 2
        }
    }
}
