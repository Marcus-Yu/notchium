import Foundation

/// A short-lived read expectation, shared by commands and external Spotify events.
/// It cannot stop polling and expires independently of the timestamps returned by Spotify.
struct PlaybackReconciliation: Sendable {
    enum Target: Sendable {
        case trackChange
        case position(Double)
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
        case .position(let position):
            guard value.hasMedia else { return false }
            if changedTrack { return true }
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
