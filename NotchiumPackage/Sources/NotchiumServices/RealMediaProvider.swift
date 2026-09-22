import AppKit
import Foundation
import NotchiumCore
import OSLog

public protocol SpotifyApplicationLaunching: Sendable {
    func isSpotifyRunning() async -> Bool
    func launchSpotify() async throws
    func localDeviceNames() async -> Set<String>
}

public final class SystemSpotifyApplicationLauncher: SpotifyApplicationLaunching, @unchecked Sendable {
    private static let bundleIdentifier = "com.spotify.client"

    public init() {}

    public func isSpotifyRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    public func launchSpotify() async throws {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.bundleIdentifier
        ) else { throw MediaFailure.spotifyUnavailable }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }

    public func localDeviceNames() -> Set<String> {
        let hostName = ProcessInfo.processInfo.hostName
        let localizedName = Host.current().localizedName
        return Set([hostName, hostName.replacingOccurrences(of: ".local", with: ""), localizedName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }
}

/// Approved public Spotify adapter.
/// One app-scoped polling task exists while authenticated, independent of subscribers.
public actor RealMediaProvider: MediaProviding {
    private static let logger = Logger(subsystem: "com.marcusyu.notchium", category: "spotify")
    private static let playingPollInterval: TimeInterval = 5
    private static let inactivePollInterval: TimeInterval = 15
    private static let transientFailurePollInterval: TimeInterval = 30
    private static let reconciliationRefreshDelays: [Duration] = [
        .milliseconds(250), .milliseconds(500), .seconds(1),
    ]
    private static let localDeviceRefreshDelays: [Duration] = [
        .milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2), .seconds(3),
    ]
    public let authorization: SpotifyAuthorization
    private let api: SpotifyPlaybackAPI
    private let clock: any AppClock
    private let applicationLauncher: any SpotifyApplicationLaunching
    private var state = MediaState(availability: .unavailable(.permissionNotDetermined),
                                   connectionState: .initializing, source: .spotify)
    private var subscribers: [UUID: AsyncStream<MediaState>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?
    private var reconciliationRefreshTask: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?
    private var pendingControls: Set<String> = []
    private var connecting = false
    private var playbackFetchInFlight = false
    private var refreshRequested = false
    private var expandedVisible = false
    private var queueFetchInFlight = false
    private var queueFetchedAt: Date?
    private var queueTrackID: String?
    private var queueRevision = 0
    #if DEBUG
    private let diagnosticID = UUID().uuidString.prefix(8)
    #endif
    private var connected = false
    private var generation = 0
    private var inputRevision = 0
    private var reconciliation: PlaybackReconciliation?
    private let playbackEvents: any SpotifyPlaybackEventProviding
    private var playbackEventsTask: Task<Void, Never>?
    private var desktopRefreshTask: Task<Void, Never>?
    private var desktopRefreshRequested = false
    private var observationRevision = 0
    private var publicationRevision = 0
    private var awaitingInitialPlaybackState = false

    public init(authorization: SpotifyAuthorization = SpotifyAuthorization(),
                transport: any MediaHTTPTransport = URLSessionMediaTransport(),
                clock: any AppClock = ContinuousAppClock(),
                applicationLauncher: any SpotifyApplicationLaunching = SystemSpotifyApplicationLauncher(),
                playbackEvents: any SpotifyPlaybackEventProviding = SpotifyDesktopPlaybackEvents()) {
        self.authorization = authorization
        api = SpotifyPlaybackAPI(authorization: authorization, transport: transport, clock: clock)
        self.clock = clock
        self.applicationLauncher = applicationLauncher
        self.playbackEvents = playbackEvents
        Self.logger.info("[Spotify] Manager initialized")
    }
    deinit {
        playbackEventsTask?.cancel()
        desktopRefreshTask?.cancel()
        pollTask?.cancel()
        reconciliationRefreshTask?.cancel()
        eventRefreshTask?.cancel()
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
        reconciliationRefreshTask?.cancel()
        reconciliationRefreshTask = nil
        cancelEventRefresh()
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
        reconciliationRefreshTask?.cancel()
        reconciliationRefreshTask = nil
        cancelEventRefresh()
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
        cancelEventRefresh()
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
        reconciliationRefreshTask?.cancel(); reconciliationRefreshTask = nil
        cancelEventRefresh()
        awaitingInitialPlaybackState = false
    }
    public func disconnect() async throws {
        generation &+= 1; connected = false; pollTask?.cancel(); pollTask = nil
        reconciliationRefreshTask?.cancel(); reconciliationRefreshTask = nil
        cancelEventRefresh()
        awaitingInitialPlaybackState = false
        await publish(.init(availability: .unavailable(.permissionNotDetermined),
                      connectionState: .unauthenticated, source: .spotify))
        try await authorization.disconnect()
    }
    private func remove(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
    @discardableResult
    private func publish(_ value: MediaState) async -> Bool {
        let generation = generation
        publicationRevision &+= 1
        let revision = publicationRevision
        let observation = observationRevision
        var value = value
        let until = connected ? await api.cooldownUntil() : nil
        guard self.generation == generation, publicationRevision == revision,
              observationRevision == observation else { return false }
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
        return true
    }
    private func startPolling() {
        startPlaybackEvents()
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
        defer { finishPlaybackFetch() }
        return .seconds(await readPlayback(reason: "poll"))
    }

    /// The only playback GET and ingestion path. Every caller uses the same revision,
    /// whole-snapshot acceptance, queue preservation, and error/cooldown handling.
    @discardableResult
    private func readPlayback(reason: String) async -> TimeInterval {
        let generation = generation
        observationRevision &+= 1
        let revision = observationRevision
        let isInitialFetch = awaitingInitialPlaybackState
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            var next = try await api.state(reason: reason)
            next.observationStartedUptime = startedAt
            guard !Task.isCancelled, connected, self.generation == generation,
                  revision == observationRevision else { return valuePollInterval(for: state) }
            awaitingInitialPlaybackState = false
            await ingestPlayback(next)
        } catch {
            guard !Task.isCancelled, self.generation == generation else { return Self.playingPollInterval }
            if let until = await api.cooldownUntil() {
                guard self.generation == generation else { return Self.playingPollInterval }
                awaitingInitialPlaybackState = false
                await publish(state)
                return max(0, until.timeIntervalSince(await clock.now()))
            }
            guard revision == observationRevision else { return valuePollInterval(for: state) }
            awaitingInitialPlaybackState = false
            var next = state
            if isInitialFetch && error as? MediaFailure != .disconnected {
                next.availability = .unavailable(.temporarilyUnavailable)
                next.connectionState = .error
            }
            if error as? MediaFailure == .authorization || error as? MediaFailure == .disconnected {
                next.capabilities = .init()
            }
            if error as? MediaFailure != .disconnected { next.issue = Self.message(error) }
            await publish(next)
            return Self.transientFailurePollInterval
        }
        return valuePollInterval(for: state)
    }

    private func valuePollInterval(for state: MediaState) -> TimeInterval {
        guard expandedVisible else {
            return state.isPlaying ? Self.playingPollInterval : Self.inactivePollInterval
        }
        return state.isPlaying ? 2.5 : (state.hasMedia ? 5 : 10)
    }
    public func setExpandedVisible(_ visible: Bool) async {
        guard !Task.isCancelled else { return }
        guard expandedVisible != visible else { return }
        expandedVisible = visible
        if visible { await refresh() }
    }
    public func perform(_ command: MediaCommand) async throws {
        guard !pendingControls.contains(command.controlID) else { throw MediaFailure.busy }
        guard connected else { throw MediaFailure.disconnected }
        pendingControls.insert(command.controlID)
        invalidatePlaybackReads()
        let input = inputRevision
        let origin = state
        let generation = generation
        if let expectation = PlaybackReconciliation(command: command, origin: origin,
                                                      uptime: ProcessInfo.processInfo.systemUptime) {
            reconciliation = expectation
        }
        defer {
            pendingControls.remove(command.controlID)
            if connected, self.generation == generation, pendingControls.isEmpty {
                if reconciliation != nil {
                    scheduleReconciliationRefresh(generation: generation, action: inputRevision)
                }
                drainRequestedRefresh()
            }
        }
        do {
            try await api.perform(command, state: origin)
        } catch {
            if self.generation == generation {
                if inputRevision == input { reconciliation = nil }
                await publish(state)
            }
            throw error
        }
        guard self.generation == generation, connected else { return }
        observationRevision &+= 1 // also invalidate reads begun during command execution
        if case .setVolume(let volume) = command {
            var next = state
            next.volumePercent = Int((min(max(volume, 0), 1) * 100).rounded())
            await publish(next)
        } else {
            await readPlayback(reason: "control-confirmation")
        }
    }

    private func invalidatePlaybackReads() {
        inputRevision &+= 1
        observationRevision &+= 1
        reconciliationRefreshTask?.cancel()
        reconciliationRefreshTask = nil
    }

    /// Resumes the current session, waking Spotify Desktop and transferring to this Mac when
    /// Spotify has no active playback device. The control guard coalesces repeated Play taps.
    public func resumePlayback() async throws {
        guard !pendingControls.contains(MediaCommand.play.controlID) else { throw MediaFailure.busy }
        guard connected else { throw MediaFailure.disconnected }
        if state.hasMedia {
            try await perform(.play)
            return
        }

        pendingControls.insert(MediaCommand.play.controlID)
        invalidatePlaybackReads()
        reconciliation = .init(origin: state, target: .playing(true), startedAt: ProcessInfo.processInfo.systemUptime)
        let generation = generation
        defer {
            pendingControls.remove(MediaCommand.play.controlID)
            if connected, self.generation == generation, pendingControls.isEmpty {
                if reconciliation != nil {
                    scheduleReconciliationRefresh(generation: generation, action: inputRevision)
                }
                drainRequestedRefresh()
            }
        }
        let existingDevices = (try? await api.devices()) ?? []
        let existingIDs = Set(existingDevices.map(\.id))
        let wasRunning = await applicationLauncher.isSpotifyRunning()
        if !wasRunning {
            do { try await applicationLauncher.launchSpotify() }
            catch { throw MediaFailure.spotifyUnavailable }
        }

        let localNames = await applicationLauncher.localDeviceNames()
        guard let device = try await waitForLocalDevice(
            existingIDs: existingIDs,
            localNames: localNames,
            allowSoleExistingComputer: wasRunning,
            generation: generation
        ) else { throw MediaFailure.spotifyUnavailable }

        try await api.transferPlayback(to: device.id, play: true)
        guard self.generation == generation, connected else { throw CancellationError() }
        observationRevision &+= 1
        await readPlayback(reason: "resume-confirmation")
    }

    private func waitForLocalDevice(
        existingIDs: Set<String>,
        localNames: Set<String>,
        allowSoleExistingComputer: Bool,
        generation: Int
    ) async throws -> SpotifyDevice? {
        for delay in [Duration.zero] + Self.localDeviceRefreshDelays {
            if delay != .zero { try await clock.sleep(for: delay) }
            try Task.checkCancellation()
            guard self.generation == generation, connected else { throw CancellationError() }
            let devices = try await api.devices()
            let computers = devices.filter {
                !$0.isRestricted && $0.type.caseInsensitiveCompare("computer") == .orderedSame
            }
            if let newlyAvailable = computers.first(where: { !existingIDs.contains($0.id) }) {
                return newlyAvailable
            }
            if let namedLocal = computers.first(where: { localNames.contains($0.name.lowercased()) }) {
                return namedLocal
            }
            if allowSoleExistingComputer, computers.count == 1 { return computers[0] }
        }
        return nil
    }
    public func refresh() async {
        guard connected else { return }
        guard pendingControls.isEmpty, !playbackFetchInFlight else {
            refreshRequested = true
            return
        }
        playbackFetchInFlight = true
        defer { finishPlaybackFetch() }
        if await api.cooldownUntil() != nil { return }
        await readPlayback(reason: "refresh")
    }

    private func finishPlaybackFetch() {
        playbackFetchInFlight = false
        drainRequestedRefresh()
    }

    private func drainRequestedRefresh() {
        guard refreshRequested, connected, pendingControls.isEmpty, !playbackFetchInFlight else { return }
        refreshRequested = false
        let generation = generation
        // Do not cancel the currently executing trailing refresh from its own defer.
        eventRefreshTask = Task { [weak self] in
            guard let self, await self.generation == generation, !Task.isCancelled else { return }
            await self.refresh()
        }
    }

    private func cancelEventRefresh() {
        reconciliationRefreshTask?.cancel()
        reconciliationRefreshTask = nil
        eventRefreshTask?.cancel()
        eventRefreshTask = nil
        playbackEventsTask?.cancel()
        playbackEventsTask = nil
        desktopRefreshTask?.cancel()
        desktopRefreshTask = nil
        desktopRefreshRequested = false
        refreshRequested = false
        reconciliation = nil
    }

    private func startPlaybackEvents() {
        guard connected, playbackEventsTask == nil else { return }
        let generation = generation
        playbackEventsTask = Task { [weak self, playbackEvents] in
            for await event in await playbackEvents.events() {
                guard !Task.isCancelled, let self, await self.generation == generation else { return }
                await self.playbackChanged(event)
            }
        }
    }

    private func playbackChanged(_ event: SpotifyPlaybackEvent) {
        guard connected else { return }
        // Consume signals independently of network latency, invalidating old reads immediately.
        invalidatePlaybackReads()
        reconciliation = .init(origin: state, target: .event(event),
                               startedAt: ProcessInfo.processInfo.systemUptime)
        desktopRefreshRequested = true
        scheduleDesktopRefresh()
    }

    private func scheduleDesktopRefresh() {
        guard connected, desktopRefreshRequested, desktopRefreshTask == nil else { return }
        desktopRefreshRequested = false
        let generation = generation
        let input = inputRevision
        desktopRefreshTask = Task { [weak self, clock] in
            await self?.refreshAfterEvent(generation: generation, input: input)
            // The first signal is immediate; subsequent signals share one trailing request.
            do { try await clock.sleep(for: .milliseconds(250)) } catch { return }
            await self?.desktopRefreshEnded(generation: generation)
        }
    }

    private func refreshAfterEvent(generation: Int, input: Int) async {
        guard self.generation == generation, !Task.isCancelled else { return }
        await refresh()
        guard self.generation == generation, inputRevision == input, pendingControls.isEmpty else { return }
        if reconciliation != nil { scheduleReconciliationRefresh(generation: generation, action: input) }
    }

    private func desktopRefreshEnded(generation: Int) {
        guard self.generation == generation else { return }
        desktopRefreshTask = nil
        if reconciliation == nil { desktopRefreshRequested = false }
        scheduleDesktopRefresh()
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

    private func ingestPlayback(_ value: MediaState) async {
        let uptime = ProcessInfo.processInfo.systemUptime
        guard reconciliation?.accepts(value, uptime: uptime) != false else { return }
        var next = value
        next.sampledUptime = uptime
        if next.isSameTrack(as: state) {
            next.queue = state.queue
            next.queueIssue = state.queueIssue
        }
        let revision = observationRevision
        let published = await publish(next)
        if published, revision == observationRevision { reconciliation = nil }
    }

    private func scheduleReconciliationRefresh(generation: Int, action: Int) {
        reconciliationRefreshTask?.cancel()
        reconciliationRefreshTask = Task { [weak self] in
            await self?.runReconciliationRefresh(generation: generation, action: action)
        }
    }

    private func runReconciliationRefresh(generation: Int, action: Int) async {
        defer {
            if !Task.isCancelled, self.generation == generation, inputRevision == action {
                reconciliationRefreshTask = nil
                reconciliation = nil // retry budget exhausted: ordinary observations always resume
            }
        }
        for delay in Self.reconciliationRefreshDelays {
            do { try await clock.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, self.generation == generation,
                  inputRevision == action, reconciliation != nil else { return }
            // refresh serializes ordinary reads and coalesces an in-flight poll.
            // Its observation revision must not cancel this action's retry budget.
            await refresh()
            if await api.cooldownUntil() != nil { return }
        }
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
    public func devices() async throws -> [SpotifyDevice] {
        guard connected else { throw MediaFailure.disconnected }
        return try await api.devices()
    }
    public func transferPlayback(to deviceID: String) async throws {
        guard !pendingControls.contains("transfer") else { throw MediaFailure.busy }
        guard connected else { throw MediaFailure.disconnected }
        let generation = generation
        let available = try await api.devices()
        guard self.generation == generation, connected else { throw CancellationError() }
        guard let device = available.first(where: { $0.id == deviceID }), !device.isRestricted else {
            throw MediaFailure.unsupported
        }
        pendingControls.insert("transfer")
        invalidatePlaybackReads()
        defer {
            pendingControls.remove("transfer")
            drainRequestedRefresh()
        }
        try await api.transferPlayback(to: deviceID)
        guard self.generation == generation, connected else { return }
        invalidatePlaybackReads()
        reconciliation = .init(origin: state, target: .device(deviceID), startedAt: ProcessInfo.processInfo.systemUptime)
        await readPlayback(reason: "transfer-confirmation")
        if reconciliation != nil { scheduleReconciliationRefresh(generation: generation, action: inputRevision) }
    }
    private static func message(_ error: any Error) -> String {
        (error as? MediaFailure)?.errorDescription ?? "Spotify could not refresh playback."
    }
}
