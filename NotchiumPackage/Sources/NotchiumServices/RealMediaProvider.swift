import Foundation
import NotchiumCore
import OSLog

/// Approved public Spotify adapter.
/// One app-scoped polling task exists while authenticated, independent of subscribers.
public actor RealMediaProvider: MediaProviding {
    private static let logger = Logger(subsystem: "com.marcusyu.notchium", category: "spotify")
    private static let playingPollInterval: TimeInterval = 5
    private static let inactivePollInterval: TimeInterval = 15
    private static let transientFailurePollInterval: TimeInterval = 30
    private static let transitionRefreshDelays: [Duration] = [
        .milliseconds(250), .milliseconds(500), .seconds(1),
    ]
    public let authorization: SpotifyAuthorization
    private let api: SpotifyPlaybackAPI
    private let clock: any AppClock
    private var state = MediaState(availability: .unavailable(.permissionNotDetermined),
                                   connectionState: .initializing, source: .spotify)
    private var subscribers: [UUID: AsyncStream<MediaState>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?
    private var transitionRefreshTask: Task<Void, Never>?
    private var pendingControls: Set<String> = []
    private var connecting = false
    private var playbackFetchInFlight = false
    private var queueFetchInFlight = false
    private var queueFetchedAt: Date?
    private var queueTrackID: String?
    private var queueRevision = 0
    #if DEBUG
    private let diagnosticID = UUID().uuidString.prefix(8)
    #endif
    private var connected = false
    private var generation = 0
    private var observationRevision = 0
    private var publicationRevision = 0
    private var awaitingInitialPlaybackState = false

    public init(authorization: SpotifyAuthorization = SpotifyAuthorization(),
                transport: any MediaHTTPTransport = URLSessionMediaTransport(),
                clock: any AppClock = ContinuousAppClock()) {
        self.authorization = authorization
        api = SpotifyPlaybackAPI(authorization: authorization, transport: transport, clock: clock)
        self.clock = clock
        Self.logger.info("[Spotify] Manager initialized")
    }
    deinit {
        pollTask?.cancel()
        transitionRefreshTask?.cancel()
    }
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
        guard !connected, !connecting, state.connectionState != .authorizing else { return }
        connecting = true
        defer { connecting = false }
        let generation = generation
        if state.connectionState != .initializing {
            await publish(.init(availability: .unavailable(.permissionNotDetermined),
                          connectionState: .initializing, source: .spotify))
        }
        do {
            try await establishAuthenticatedSession(generation: generation)
        } catch {
            guard self.generation == generation else { throw CancellationError() }
            if case MediaFailure.rateLimited(let seconds) = error {
                // Stored credentials still exist when token restoration is throttled.
                // Let the same playback loop retry token acquisition after the cooldown.
                await api.recordCooldown(seconds: seconds)
                guard self.generation == generation else { throw CancellationError() }
                connected = true
                awaitingInitialPlaybackState = true
                await publish(.init(connectionState: .authenticated, source: .spotify))
                startPolling()
                return
            }
            connected = false
            if error as? MediaFailure == .disconnected {
                await publish(.init(availability: .unavailable(.permissionNotDetermined),
                              connectionState: .unauthenticated, source: .spotify))
            } else {
                await publish(.init(availability: .unavailable(.temporarilyUnavailable),
                              connectionState: .error, source: .spotify, issue: Self.message(error)))
            }
            throw error
        }
    }
    public func beginAuthorization(clientID: String) async throws -> URL {
        generation &+= 1
        let generation = generation
        connected = false
        pollTask?.cancel()
        pollTask = nil
        transitionRefreshTask?.cancel()
        transitionRefreshTask = nil
        awaitingInitialPlaybackState = false
        await publish(.init(availability: .unavailable(.permissionNotDetermined),
                      connectionState: .authorizing, source: .spotify))
        do {
            let url = try await authorization.begin(clientID: clientID)
            guard self.generation == generation else { throw CancellationError() }
            return url
        } catch {
            guard self.generation == generation else { throw CancellationError() }
            await publish(.init(availability: .unavailable(.temporarilyUnavailable),
                          connectionState: .error, source: .spotify, issue: Self.message(error)))
            throw error
        }
    }
    public func completeAuthorization(callback: URL) async throws {
        let generation = generation
        guard state.connectionState == .authorizing else { throw MediaFailure.authorization }
        do {
            try await authorization.complete(callback: callback)
            try Task.checkCancellation()
            guard self.generation == generation else { throw CancellationError() }
            try await establishAuthenticatedSession(generation: generation)
        } catch {
            guard self.generation == generation else { throw CancellationError() }
            connected = false
            awaitingInitialPlaybackState = false
            await publish(.init(availability: .unavailable(.temporarilyUnavailable),
                          connectionState: .error, source: .spotify, issue: Self.message(error)))
            throw error
        }
    }
    public func cancelAuthorization() async {
        guard state.connectionState == .authorizing else { return }
        generation &+= 1
        connected = false
        pollTask?.cancel()
        pollTask = nil
        transitionRefreshTask?.cancel()
        transitionRefreshTask = nil
        awaitingInitialPlaybackState = false
        await authorization.cancelAuthorizationAttempt()
        await publish(.init(availability: .unavailable(.permissionNotDetermined),
                      connectionState: .unauthenticated, source: .spotify))
    }
    public func failAuthorization() async {
        guard state.connectionState == .authorizing else { return }
        generation &+= 1
        connected = false
        pollTask?.cancel()
        pollTask = nil
        awaitingInitialPlaybackState = false
        await authorization.cancelAuthorizationAttempt()
        await publish(.init(availability: .unavailable(.temporarilyUnavailable),
                      connectionState: .error, source: .spotify,
                      issue: MediaFailure.authorization.errorDescription))
    }
    private func establishAuthenticatedSession(generation: Int) async throws {
        _ = try await authorization.accessToken()
        try Task.checkCancellation()
        guard self.generation == generation else { throw CancellationError() }
        connected = true
        queueFetchedAt = nil
        awaitingInitialPlaybackState = true
        await publish(.init(connectionState: .authenticated, source: .spotify))
        Self.logger.info("[Spotify] Session authenticated")
        startPolling()
    }
    public func shutdown() async {
        generation &+= 1; connected = false; pollTask?.cancel(); pollTask = nil
        transitionRefreshTask?.cancel(); transitionRefreshTask = nil
        awaitingInitialPlaybackState = false
    }
    public func disconnect() async throws {
        generation &+= 1; connected = false; pollTask?.cancel(); pollTask = nil
        transitionRefreshTask?.cancel(); transitionRefreshTask = nil
        awaitingInitialPlaybackState = false
        await publish(.init(availability: .unavailable(.permissionNotDetermined),
                      connectionState: .unauthenticated, source: .spotify))
        try await authorization.disconnect()
    }
    private func remove(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
    private func publish(_ value: MediaState) async {
        let generation = generation
        publicationRevision &+= 1
        let revision = publicationRevision
        var value = value
        let until = connected ? await api.cooldownUntil() : nil
        guard self.generation == generation, publicationRevision == revision else { return }
        if let until {
            value.connectionState = .authenticated
            value.availability = .available
            value.rateLimitedUntil = until
            value.issue = "Spotify API temporarily rate limited. Retry after \(until.formatted(date: .omitted, time: .shortened))."
        } else if value.rateLimitedUntil != nil {
            value.rateLimitedUntil = nil
            value.issue = nil
        }
        if state != value { state = value }
        for continuation in subscribers.values { continuation.yield(value) }
    }
    private func startPolling() {
        guard pollTask == nil, connected else { return }
        let generation = generation
        pollTask = Task { [weak self, clock] in
            #if DEBUG
            Self.logger.debug("[SpotifyPoll] provider=\(self?.diagnosticID ?? "released", privacy: .public) generation=\(generation) started")
            #endif
            while !Task.isCancelled {
                guard let delay = await self?.poll(generation: generation) else { break }
                do { try await clock.sleep(for: delay) } catch { break }
            }
            await self?.pollingEnded(generation: generation)
        }
    }
    private func pollingEnded(generation: Int) {
        if self.generation == generation { pollTask = nil }
        #if DEBUG
        Self.logger.debug("[SpotifyPoll] provider=\(self.diagnosticID, privacy: .public) generation=\(generation) ended")
        #endif
    }
    private func poll(generation: Int) async -> Duration? {
        guard connected, self.generation == generation else { return nil }
        if let until = await api.cooldownUntil() {
            await publish(state)
            return .seconds(max(0, until.timeIntervalSince(await clock.now())))
        }
        guard pendingControls.isEmpty, !playbackFetchInFlight else {
            return .seconds(Self.playingPollInterval)
        }
        playbackFetchInFlight = true
        defer { playbackFetchInFlight = false }
        #if DEBUG
        Self.logger.debug("[SpotifyPoll] provider=\(self.diagnosticID, privacy: .public) generation=\(generation) cycle")
        #endif
        let revision = observationRevision
        let isInitialFetch = awaitingInitialPlaybackState
        if isInitialFetch { Self.logger.info("[Spotify] Fetching playback state") }
        do {
            let value = try await api.state(reason: "poll")
            guard !Task.isCancelled, self.generation == generation else { return nil }
            guard revision == observationRevision else { return .seconds(Self.playingPollInterval) }
            awaitingInitialPlaybackState = false
            var next = value
            if next.isSameTrack(as: state) {
                next.queue = state.queue
                next.queueIssue = state.queueIssue
            }
            await publish(next)
            if isInitialFetch && !next.hasMedia {
                Self.logger.info("[Spotify] No active playback")
            }
        } catch {
            guard !Task.isCancelled, self.generation == generation else { return nil }
            if let until = await api.cooldownUntil() {
                awaitingInitialPlaybackState = false
                await publish(state)
                return .seconds(max(0, until.timeIntervalSince(await clock.now())))
            }
            guard revision == observationRevision else { return .seconds(Self.playingPollInterval) }
            awaitingInitialPlaybackState = false
            var next = state
            if error as? MediaFailure == .authorization {
                next = .init(availability: .unavailable(.temporarilyUnavailable),
                             connectionState: .error, source: .spotify)
            } else if error as? MediaFailure == .disconnected {
                next = .init(connectionState: .authenticated, source: .spotify)
            } else if isInitialFetch {
                next.availability = .unavailable(.temporarilyUnavailable)
                next.connectionState = .error
            }
            if error as? MediaFailure != .disconnected {
                next.issue = Self.message(error)
            }
            await publish(next)
            if error as? MediaFailure == .authorization {
                connected = false; pollTask = nil; return nil
            }
            return .seconds(Self.transientFailurePollInterval)
        }
        let interval = valuePollInterval(for: state)
        return .seconds(interval)
    }

    private func valuePollInterval(for state: MediaState) -> TimeInterval {
        state.isPlaying ? Self.playingPollInterval : Self.inactivePollInterval
    }
    public func perform(_ command: MediaCommand) async throws {
        guard !pendingControls.contains(command.controlID) else { throw MediaFailure.busy }
        guard connected else { throw MediaFailure.disconnected }
        pendingControls.insert(command.controlID)
        observationRevision &+= 1
        defer { pendingControls.remove(command.controlID) }
        let generation = generation
        do {
            if case .seek(let seconds) = command {
                let target = min(max(seconds, 0), state.validDuration ?? 0)
                #if DEBUG
                print("[SpotifySeek] requested \(target)s")
                #endif
            }
            try await api.perform(command, state: state)
            guard self.generation == generation, connected else { return }
            observationRevision &+= 1
            let revision = observationRevision
            let origin = state
            var next = try await api.state(reason: "control-confirmation")
            guard self.generation == generation, revision == observationRevision else { return }
            let isTrackTransition = command == .next || command == .previous
            if isTrackTransition, (!next.hasMedia || next.isSameTrack(as: origin)) {
                // Spotify can briefly expose no item (or the old item) after a skip. Keep the
                // last valid snapshot published while a few bounded, action-triggered refreshes
                // look for the new track. Normal polling remains unchanged.
                next = origin
                scheduleTransitionRefresh(origin: origin, generation: generation,
                                          revision: revision)
            } else if next.isSameTrack(as: state) {
                next.queue = state.queue
                next.queueIssue = state.queueIssue
            }
            await publish(next)
            if case .seek = command {
                #if DEBUG
                print("[SpotifySeek] refreshed position \(next.elapsedTime)s")
                #endif
            }
        } catch {
            if self.generation == generation { await publish(state) }
            throw error
        }
    }
    public func refresh() async {
        guard connected, !playbackFetchInFlight, pendingControls.isEmpty else { return }
        playbackFetchInFlight = true
        defer { playbackFetchInFlight = false }
        if await api.cooldownUntil() != nil { return }
        let generation = generation
        observationRevision &+= 1
        let revision = observationRevision
        do {
            var next = try await api.state(reason: "refresh")
            guard self.generation == generation, revision == observationRevision else { return }
            if next.isSameTrack(as: state) {
                next.queue = state.queue
                next.queueIssue = state.queueIssue
            }
            await publish(next)
        } catch {
            guard self.generation == generation else { return }
            if await api.cooldownUntil() != nil { await publish(state); return }
            guard revision == observationRevision else { return }
            if error as? MediaFailure == .disconnected || error as? MediaFailure == .authorization {
                var next = state
                next.capabilities = .init()
                await publish(next)
            }
        }
    }
    public func loadQueue() async throws {
        try await fetchQueue(force: false)
    }
    public func refreshQueue() async throws {
        try await fetchQueue(force: true)
    }
    private func fetchQueue(force: Bool) async throws {
        guard state.capabilities.canReadQueue else { throw MediaFailure.unsupported }
        guard connected else { throw MediaFailure.disconnected }
        guard !queueFetchInFlight else { return }
        queueFetchInFlight = true
        defer { queueFetchInFlight = false }
        let generation = generation
        // Coalesce opens/track events during a request. If its snapshot became stale,
        // fetch the latest queue once, without starting another task or timer.
        for _ in 0..<2 {
            let id = state.trackID
            let revision = queueRevision
            if !force, queueTrackID == id, let queueFetchedAt,
               (await clock.now()).timeIntervalSince(queueFetchedAt) < 15 { return }
            do {
                let queue = try await api.queue()
                let observedAt = await clock.now()
                guard !Task.isCancelled, self.generation == generation, connected else { return }
                guard state.trackID == id, queueRevision == revision else { continue }
                queueFetchedAt = observedAt
                queueTrackID = id
                var next = state
                next.queue = queue
                next.queueIssue = nil
                await publish(next)
                return
            } catch {
                guard !Task.isCancelled, self.generation == generation else { return }
                var next = state
                next.queueIssue = "Unavailable"
                await publish(next)
                throw error
            }
        }
    }

    private func scheduleTransitionRefresh(origin: MediaState, generation: Int, revision: Int) {
        transitionRefreshTask?.cancel()
        transitionRefreshTask = Task { [weak self] in
            await self?.runTransitionRefresh(origin: origin, generation: generation,
                                             revision: revision)
        }
    }

    private func runTransitionRefresh(origin: MediaState, generation: Int, revision: Int) async {
        for delay in Self.transitionRefreshDelays {
            do { try await clock.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, self.generation == generation,
                  observationRevision == revision else { return }
            do {
                var next = try await api.state(reason: "transition")
                guard self.generation == generation, observationRevision == revision else { return }
                guard next.hasMedia, !next.isSameTrack(as: origin) else { continue }
                if next.isSameTrack(as: state) {
                    next.queue = state.queue
                    next.queueIssue = state.queueIssue
                }
                await publish(next)
                transitionRefreshTask = nil
                return
            } catch {
                guard self.generation == generation else { return }
                if await api.cooldownUntil() != nil { await publish(state) }
                return
            }
        }
        guard self.generation == generation, observationRevision == revision else { return }
        transitionRefreshTask = nil
    }
    public func addToQueue(uri: String) async throws {
        guard connected else { throw MediaFailure.disconnected }
        let generation = generation
        do {
            try await api.addToQueue(uri: uri, deviceID: state.activeDeviceID)
            guard self.generation == generation else { return }
            queueFetchedAt = nil
            queueRevision &+= 1
            try await loadQueue()
        } catch {
            if self.generation == generation { await publish(state) }
            throw error
        }
    }
    private static func message(_ error: any Error) -> String {
        (error as? MediaFailure)?.errorDescription ?? "Spotify could not refresh playback."
    }
}
