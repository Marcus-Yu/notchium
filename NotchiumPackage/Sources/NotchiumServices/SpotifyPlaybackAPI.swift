import Foundation
import NotchiumCore
import OSLog

struct SpotifyPlayback: Decodable {
    struct Artist: Decodable { let name: String }
    struct Artwork: Decodable { let url: URL; let width: Int? }
    struct Album: Decodable { let images: [Artwork] }
    struct Track: Decodable {
        let id: String?
        let uri: String?
        let name: String
        let artists: [Artist]?
        let duration_ms: Double?
        let album: Album?
        let type: String?
    }
    struct Device: Decodable {
        let id: String?
        let is_active: Bool?
        let is_restricted: Bool?
        let name: String?
        let type: String?
        let volume_percent: Int?
        let supports_volume: Bool?
    }
    struct Actions: Decodable { let disallows: [String: Bool]? }
    let is_playing: Bool
    let progress_ms: Double?
    let item: Track?
    let device: Device?
    let actions: Actions?
    let shuffle_state: Bool?
    let repeat_state: String?

    // Spotify's timestamp is the last transport change, not the sampling time of progress_ms.
    // Pair the current progress with observation receipt to avoid counting playback twice.
    func mediaState(observedAt: Date = Date()) -> MediaState {
        guard let item, item.type == nil || item.type == "track" else { return .init(source: .spotify) }
        let disallows = actions?.disallows ?? [:]
        let controllable = device != nil && device?.is_restricted != true
        func allows(_ name: String) -> Bool { controllable && disallows[name] != true }
        return .init(connectionState: .authenticated,
                     playbackState: is_playing ? .playing : .paused, title: item.name,
                     artist: item.artists?.map(\.name).joined(separator: ", "),
                     elapsed: (progress_ms ?? 0) / 1000, duration: item.duration_ms.map { $0 / 1000 },
                     trackID: item.id, activeDeviceID: device?.id,
                     activeDeviceName: device?.name, activeDeviceType: device?.type,
                     volumePercent: device?.volume_percent,
                     artwork: item.album?.images.min {
                         abs(($0.width ?? 300) - 300) < abs(($1.width ?? 300) - 300)
                     }?.url, source: .spotify,
                     capabilities: .init(canPlayPause: allows(is_playing ? "pausing" : "resuming"),
                                         canSkipForward: allows("skipping_next"), canSkipBackward: allows("skipping_prev"),
                                         canSeek: allows("seeking"), canShuffle: allows("toggling_shuffle"),
                                         canRepeat: allows("toggling_repeat_context") && allows("toggling_repeat_track"),
                                         canReadQueue: true,
                                         canSetVolume: controllable && device?.supports_volume == true),
                     shuffle: shuffle_state, repeatMode: repeat_state.flatMap(MediaRepeatMode.init(rawValue:)),
                     timestamp: observedAt, playbackRate: is_playing ? 1 : 0)
    }
}

actor SpotifyPlaybackAPI {
    private static let logger = Logger(subsystem: "com.marcusyu.notchium", category: "spotify")
    private let clock: any AppClock
    private var rateLimitedUntil: Date?
    #if DEBUG
    private let diagnosticID = UUID().uuidString.prefix(8)
    private var requestCount = 0
    #endif
    let authorization: SpotifyAuthorization
    let transport: any MediaHTTPTransport
    init(authorization: SpotifyAuthorization, transport: any MediaHTTPTransport,
         clock: any AppClock = ContinuousAppClock()) {
        self.authorization = authorization; self.transport = transport; self.clock = clock
    }

    func cooldownUntil() async -> Date? {
        let now = await clock.now()
        guard let until = rateLimitedUntil, until > now else { return nil }
        return until
    }

    private func checkCooldown() async throws {
        let now = await clock.now()
        if let until = rateLimitedUntil, until > now {
            throw MediaFailure.rateLimited(Int(ceil(until.timeIntervalSince(now))))
        }
    }

    func request(path: String = "", method: String = "GET", query: [URLQueryItem] = [],
                 body: Data? = nil, reason: String = "direct") async throws -> MediaHTTPResponse {
        try Task.checkCancellation()
        try await checkCooldown()
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player" + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            request.setValue("Bearer \(try await authorization.accessToken())", forHTTPHeaderField: "Authorization")
        } catch MediaFailure.rateLimited(let seconds) {
            await recordCooldown(seconds: seconds)
            throw MediaFailure.rateLimited(seconds)
        }
        // Token acquisition suspends the actor. Another endpoint may have received 429 meanwhile.
        try Task.checkCancellation()
        try await checkCooldown()
        #if DEBUG
        requestCount += 1
        let number = requestCount
        Self.logger.debug("[SpotifyAPI] client=\(self.diagnosticID, privacy: .public) request=\(number) reason=\(reason, privacy: .public) \(method, privacy: .public) /me/player\(path, privacy: .public)")
        #endif
        let response = try await transport.send(request)
        #if DEBUG
        Self.logger.debug("[SpotifyAPI] client=\(self.diagnosticID, privacy: .public) request=\(number) status=\(response.status) retryAfter=\(response.retryAfter ?? 0)")
        #endif
        if response.status == 429 {
            // Record every actual 429 before any caller can discard a stale playback response.
            await recordCooldown(seconds: max(1, response.retryAfter ?? 30))
        }
        switch response.status {
        case 200..<300: return response
        case 401: throw MediaFailure.authorization
        case 403: throw MediaFailure.unsupported
        case 404: throw MediaFailure.disconnected
        case 429: throw MediaFailure.rateLimited(max(1, response.retryAfter ?? 30))
        default: throw MediaFailure.invalidResponse
        }
    }
    func recordCooldown(seconds: Int) async {
        let until = await clock.now().addingTimeInterval(Double(seconds))
        rateLimitedUntil = max(rateLimitedUntil ?? until, until)
    }

    func state(reason: String = "direct") async throws -> MediaState {
        let response = try await request(reason: reason)
        if response.status == 204 {
            return .init(connectionState: .authenticated, source: .spotify)
        }
        return try JSONDecoder().decode(SpotifyPlayback.self, from: response.data).mediaState()
    }
    func queue() async throws -> [QueueTrack] {
        struct Queue: Decodable {
            let currently_playing: SpotifyPlayback.Track?
            let queue: [SpotifyPlayback.Track]
        }
        let response = try await request(path: "/queue", reason: "queue")
        let payload = try JSONDecoder().decode(Queue.self, from: response.data)
        var occurrences: [String: Int] = [:]
        return payload.queue.prefix(20).compactMap { track in
            guard track.type == nil || track.type == "track", let uri = track.uri, !uri.isEmpty else { return nil }
            let identity = track.id ?? uri
            let occurrence = occurrences[identity, default: 0]
            occurrences[identity] = occurrence + 1
            return .init(id: "\(identity):\(occurrence)", uri: uri, title: track.name,
                         artist: track.artists?.map(\.name).joined(separator: ", ") ?? "",
                         artworkURL: track.album?.images.min {
                             abs(($0.width ?? 300) - 300) < abs(($1.width ?? 300) - 300)
                         }?.url,
                         duration: max(0, (track.duration_ms ?? 0) / 1000))
        }
    }
    func addToQueue(uri: String, deviceID: String? = nil) async throws {
        guard !uri.isEmpty else { throw MediaFailure.unsupported }
        var query = [URLQueryItem(name: "uri", value: uri)]
        if let deviceID { query.append(.init(name: "device_id", value: deviceID)) }
        let response = try await request(path: "/queue", method: "POST",
                                         query: query, reason: "command")
        guard response.status == 204 else { throw MediaFailure.invalidResponse }
    }
    func devices() async throws -> [SpotifyDevice] {
        struct Payload: Decodable { let devices: [SpotifyPlayback.Device] }
        let response = try await request(path: "/devices", reason: "devices")
        return try JSONDecoder().decode(Payload.self, from: response.data).devices.compactMap { device in
            guard let id = device.id, !id.isEmpty else { return nil }
            return SpotifyDevice(id: id, name: device.name ?? "Spotify device",
                                 type: device.type ?? "unknown", isActive: device.is_active == true,
                                 isRestricted: device.is_restricted == true,
                                 volumePercent: device.volume_percent,
                                 supportsVolume: device.supports_volume == true)
        }
    }
    func transferPlayback(to deviceID: String) async throws {
        guard !deviceID.isEmpty else { throw MediaFailure.unsupported }
        let body = try JSONEncoder().encode(["device_ids": [deviceID]])
        let response = try await request(method: "PUT", body: body, reason: "transfer")
        guard response.status == 204 else { throw MediaFailure.invalidResponse }
    }
    func perform(_ command: MediaCommand, state: MediaState) async throws {
        guard state.hasMedia, state.capabilities.supports(command) else { throw MediaFailure.unsupported }
        let path: String
        var method = "PUT"
        var query: [URLQueryItem] = []
        switch command {
        case .play: path = "/play"
        case .pause: path = "/pause"
        case .setShuffle(let enabled):
            path = "/shuffle"; query = [.init(name: "state", value: String(enabled))]
        case .setRepeatMode(let mode):
            path = "/repeat"; query = [.init(name: "state", value: mode.rawValue)]
        case .playPause: path = state.isPlaying ? "/pause" : "/play"
        case .previous: path = "/previous"; method = "POST"
        case .next: path = "/next"; method = "POST"
        case .seek(let seconds):
            guard seconds.isFinite, let duration = state.validDuration else { throw MediaFailure.unsupported }
            path = "/seek"
            query = [.init(name: "position_ms", value: String(Int(min(max(0, seconds), duration) * 1000)))]
            if let deviceID = state.activeDeviceID {
                query.append(.init(name: "device_id", value: deviceID))
            }
        case .toggleShuffle:
            path = "/shuffle"; query = [.init(name: "state", value: state.shuffle == true ? "false" : "true")]
        case .cycleRepeat:
            path = "/repeat"
            let next: MediaRepeatMode = state.repeatMode == .off ? .context : state.repeatMode == .context ? .track : .off
            query = [.init(name: "state", value: next.rawValue)]
        case .setVolume(let value):
            guard value.isFinite, state.capabilities.canSetVolume else { throw MediaFailure.unsupported }
            path = "/volume"
            let percent = Int((min(max(value, 0), 1) * 100).rounded())
            query = [.init(name: "volume_percent", value: String(percent))]
            if let deviceID = state.activeDeviceID {
                query.append(.init(name: "device_id", value: deviceID))
            }
        }
        let response = try await request(path: path, method: method, query: query, reason: "command")
        if case .seek = command {
            guard response.status == 204 else { throw MediaFailure.invalidResponse }
        }
    }
}
