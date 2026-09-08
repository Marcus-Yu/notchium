import Foundation

struct SpotifyPlayback: Decodable {
    struct Artist: Decodable { let name: String }
    struct Artwork: Decodable { let url: URL; let width: Int? }
    struct Album: Decodable { let images: [Artwork] }
    struct Track: Decodable {
        let id: String?
        let name: String
        let artists: [Artist]?
        let duration_ms: Double?
        let album: Album?
        let type: String?
    }
    struct Device: Decodable { let is_restricted: Bool? }
    struct Actions: Decodable { let disallows: [String: Bool]? }
    let is_playing: Bool
    let progress_ms: Double?
    let item: Track?
    let device: Device?
    let actions: Actions?
    let shuffle_state: Bool?
    let repeat_state: String?

    func mediaState() -> MediaState {
        guard let item, item.type == nil || item.type == "track" else { return .init(source: .spotify) }
        let disallows = actions?.disallows ?? [:]
        let controllable = device != nil && device?.is_restricted != true
        func allows(_ name: String) -> Bool { controllable && disallows[name] != true }
        return .init(playbackState: is_playing ? .playing : .paused, title: item.name,
                     artist: item.artists?.map(\.name).joined(separator: ", "),
                     elapsed: (progress_ms ?? 0) / 1000, duration: item.duration_ms.map { $0 / 1000 },
                     trackID: item.id, artwork: item.album?.images.min {
                         abs(($0.width ?? 300) - 300) < abs(($1.width ?? 300) - 300)
                     }?.url, source: .spotify,
                     capabilities: .init(canPlayPause: allows(is_playing ? "pausing" : "resuming"),
                                         canSkipForward: allows("skipping_next"), canSkipBackward: allows("skipping_prev"),
                                         canSeek: allows("seeking"), canShuffle: allows("toggling_shuffle"),
                                         canRepeat: allows("toggling_repeat_context") && allows("toggling_repeat_track"),
                                         canReadQueue: true),
                     shuffle: shuffle_state, repeatMode: repeat_state.flatMap(MediaRepeatMode.init(rawValue:)))
    }
}

struct SpotifyPlaybackAPI: Sendable {
    let authorization: SpotifyAuthorization
    let transport: any MediaHTTPTransport
    func request(path: String = "", method: String = "GET", query: [URLQueryItem] = []) async throws -> MediaHTTPResponse {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player" + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await authorization.accessToken())", forHTTPHeaderField: "Authorization")
        let response = try await transport.send(request)
        switch response.status {
        case 200..<300: return response
        case 401: throw MediaFailure.authorization
        case 403: throw MediaFailure.unsupported
        case 404: throw MediaFailure.disconnected
        case 429: throw MediaFailure.rateLimited(max(1, response.retryAfter ?? 30))
        default: throw MediaFailure.invalidResponse
        }
    }
    func state() async throws -> MediaState {
        let response = try await request()
        if response.status == 204 { return .init(source: .spotify) }
        return try JSONDecoder().decode(SpotifyPlayback.self, from: response.data).mediaState()
    }
    func queue() async throws -> [MediaQueueItem] {
        struct Queue: Decodable { let queue: [SpotifyPlayback.Track] }
        let response = try await request(path: "/queue")
        return try JSONDecoder().decode(Queue.self, from: response.data).queue.prefix(20).enumerated().map {
            .init(id: "\($0.offset):\($0.element.id ?? "local")", title: $0.element.name,
                  artist: $0.element.artists?.map(\.name).joined(separator: ", ") ?? "")
        }
    }
    func perform(_ command: MediaCommand, state: MediaState) async throws {
        guard state.hasMedia, state.capabilities.supports(command) else { throw MediaFailure.unsupported }
        let path: String
        var method = "PUT"
        var query: [URLQueryItem] = []
        switch command {
        case .playPause: path = state.isPlaying ? "/pause" : "/play"
        case .previous: path = "/previous"; method = "POST"
        case .next: path = "/next"; method = "POST"
        case .seek(let seconds):
            guard seconds.isFinite, let duration = state.validDuration else { throw MediaFailure.unsupported }
            path = "/seek"
            query = [.init(name: "position_ms", value: String(Int(min(max(0, seconds), duration) * 1000)))]
        case .toggleShuffle:
            path = "/shuffle"; query = [.init(name: "state", value: state.shuffle == true ? "false" : "true")]
        case .cycleRepeat:
            path = "/repeat"
            let next: MediaRepeatMode = state.repeatMode == .off ? .context : state.repeatMode == .context ? .track : .off
            query = [.init(name: "state", value: next.rawValue)]
        case .setVolume: throw MediaFailure.unsupported
        }
        _ = try await request(path: path, method: method, query: query)
    }
}
