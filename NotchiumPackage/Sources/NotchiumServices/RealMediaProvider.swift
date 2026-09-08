import Foundation
import NotchiumCore

/// Approved public Spotify adapter. MusicKit.SystemMusicPlayer is unavailable on macOS.
/// One polling task exists only while connected and subscribed; no audio is captured.
public actor RealMediaProvider: MediaProviding {
    public static let appleMusicLimitation = "Apple Music observation is unavailable: MusicKit.SystemMusicPlayer is marked unavailable on macOS."
    public let authorization: SpotifyAuthorization
    private let api: SpotifyPlaybackAPI
    private let clock: any AppClock
    private var state = MediaState(availability: .unavailable(.permissionNotDetermined))
    private var subscribers: [UUID: AsyncStream<MediaState>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?
    private var commandInFlight = false
    private var retryAt: Date?
    private var connected = false
    private var generation = 0
    private var observationRevision = 0

    public init(authorization: SpotifyAuthorization = SpotifyAuthorization(),
                transport: any MediaHTTPTransport = URLSessionMediaTransport(),
                clock: any AppClock = ContinuousAppClock()) {
        self.authorization = authorization
        api = SpotifyPlaybackAPI(authorization: authorization, transport: transport)
        self.clock = clock
    }
    deinit { pollTask?.cancel() }
    public func availability() -> FeatureAvailability { state.availability }
    public func updates() -> AsyncStream<MediaState> {
        let id = UUID()
        let pair = AsyncStream<MediaState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = pair.continuation; pair.continuation.yield(state)
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        if connected { startPolling() }
        return pair.stream
    }
    public func connect() async throws {
        let generation = generation
        _ = try await authorization.accessToken()
        try Task.checkCancellation()
        guard self.generation == generation else { throw CancellationError() }
        connected = true
        startPolling()
    }
    public func disconnect() async throws {
        generation &+= 1; connected = false; pollTask?.cancel(); pollTask = nil
        publish(.init(availability: .unavailable(.permissionNotDetermined)))
        try await authorization.disconnect()
    }
    private func remove(_ id: UUID) {
        subscribers.removeValue(forKey: id)
        if subscribers.isEmpty { generation &+= 1; pollTask?.cancel(); pollTask = nil }
    }
    private func publish(_ value: MediaState) {
        if state != value { state = value }
        for continuation in subscribers.values { continuation.yield(value) }
    }
    private func startPolling() {
        guard pollTask == nil, !subscribers.isEmpty else { return }
        let generation = generation
        pollTask = Task { [weak self, clock] in
            while !Task.isCancelled {
                guard let delay = await self?.poll(generation: generation) else { return }
                do { try await clock.sleep(for: delay) } catch { return }
            }
        }
    }
    private func poll(generation: Int) async -> Duration? {
        guard connected, self.generation == generation else { return nil }
        if let retryAt, retryAt > (await clock.now()) { return .seconds(5) }
        guard !commandInFlight else { return .seconds(5) }
        let revision = observationRevision
        do {
            let value = try await api.state()
            guard !Task.isCancelled, self.generation == generation else { return nil }
            guard revision == observationRevision else { return .seconds(5) }
            var next = value
            if next.trackID == state.trackID { next.queue = state.queue }
            publish(next)
        } catch {
            guard !Task.isCancelled, self.generation == generation else { return nil }
            guard revision == observationRevision else { return .seconds(5) }
            if case MediaFailure.rateLimited(let seconds) = error {
                retryAt = await clock.now().addingTimeInterval(Double(seconds))
            }
            publish(.init(availability: .unavailable(.temporarilyUnavailable), issue: Self.message(error)))
            if error as? MediaFailure == .authorization || error as? MediaFailure == .disconnected {
                connected = false; pollTask = nil; return nil
            }
            return .seconds(30)
        }
        return state.isPlaying ? .seconds(5) : .seconds(15)
    }
    public func perform(_ command: MediaCommand) async throws {
        guard !commandInFlight else { throw MediaFailure.busy }
        if let retryAt, retryAt > (await clock.now()) { throw MediaFailure.rateLimited(30) }
        commandInFlight = true
        observationRevision &+= 1
        defer { commandInFlight = false }
        let generation = generation
        do {
            try await api.perform(command, state: state)
            let next = try await api.state()
            guard self.generation == generation else { return }
            publish(next) // Never pretend a command or seek succeeded before confirmed observation.
        } catch {
            if case MediaFailure.rateLimited(let seconds) = error {
                retryAt = await clock.now().addingTimeInterval(Double(seconds))
            }
            throw error
        }
    }
    public func loadQueue() async throws {
        guard state.capabilities.canReadQueue else { throw MediaFailure.unsupported }
        if let retryAt, retryAt > (await clock.now()) { throw MediaFailure.rateLimited(30) }
        let id = state.trackID
        let generation = generation
        do {
            let queue = try await api.queue()
            guard !Task.isCancelled, self.generation == generation, state.trackID == id, connected else { return }
            var next = state; next.queue = queue; publish(next)
        } catch {
            guard !Task.isCancelled, self.generation == generation else { return }
            if case MediaFailure.rateLimited(let seconds) = error {
                retryAt = await clock.now().addingTimeInterval(Double(seconds))
            }
            var next = state; next.capabilities.canReadQueue = false; next.queue = nil; publish(next)
            throw error
        }
    }
    private static func message(_ error: any Error) -> String {
        (error as? MediaFailure)?.errorDescription ?? "Spotify could not refresh playback."
    }
}
