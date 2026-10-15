import Foundation
import NotchiumCore

/// One provider owns observations, command reconciliation, event coalescing and fallback refresh.
public actor RealMediaProvider: MediaProviding {
    private let controller: LocalSpotifyController
    private let clock: any AppClock
    private let playbackEvents: any SpotifyPlaybackEventProviding
    private let lifecycleEvents: any SpotifyLifecycleEventProviding
    private var state = MediaState(availability: .unavailable(.permissionNotDetermined),
                                   connectionState: .initializing, source: .spotify)
    private var subscribers: [UUID: AsyncStream<MediaState>.Continuation] = [:]
    private var running = false
    private var sleeping = false
    private var expandedVisible = false
    private var generation = 0
    private var observationRevision = 0
    private var inputRevision = 0
    private var playbackFetchInFlight = false
    private var refreshRequested = false
    private var pendingControls: Set<String> = []
    private var reconciliation: PlaybackReconciliation?
    private var pollTask: Task<Void, Never>?
    private var playbackEventsTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?
    private var reconciliationTask: Task<Void, Never>?

    public init(controller: LocalSpotifyController = LocalSpotifyController(),
                clock: any AppClock = ContinuousAppClock(),
                playbackEvents: any SpotifyPlaybackEventProviding = SpotifyDesktopPlaybackEvents(),
                lifecycleEvents: any SpotifyLifecycleEventProviding = SpotifyWorkspaceEvents()) {
        self.controller = controller; self.clock = clock
        self.playbackEvents = playbackEvents; self.lifecycleEvents = lifecycleEvents
    }
    deinit {
        pollTask?.cancel(); playbackEventsTask?.cancel(); lifecycleTask?.cancel()
        eventRefreshTask?.cancel(); reconciliationTask?.cancel()
    }
    public func availability() -> FeatureAvailability { state.availability }
    public func updates() -> AsyncStream<MediaState> {
        let id = UUID()
        let pair = AsyncStream<MediaState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = pair.continuation
        pair.continuation.yield(state)
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        return pair.stream
    }
    private func remove(_ id: UUID) { subscribers.removeValue(forKey: id) }
    private func publish(_ next: MediaState) {
        state = next
        for subscriber in subscribers.values { subscriber.yield(next) }
    }

    public func connect() async throws {
        guard !running else { return }
        running = true
        sleeping = false
        startEvents()
        await refresh()
    }
    public func shutdown() {
        running = false
        generation &+= 1; observationRevision &+= 1; inputRevision &+= 1
        pollTask?.cancel(); pollTask = nil
        playbackEventsTask?.cancel(); playbackEventsTask = nil
        lifecycleTask?.cancel(); lifecycleTask = nil
        eventRefreshTask?.cancel(); eventRefreshTask = nil
        reconciliationTask?.cancel(); reconciliationTask = nil
        reconciliation = nil; refreshRequested = false; playbackFetchInFlight = false
        pendingControls.removeAll()
    }
    public func disconnect() async throws {
        shutdown()
        await controller.disable()
        try await connect()
    }
    public func enableLocalControl() async throws {
        guard !pendingControls.contains("authorization") else { throw MediaFailure.busy }
        if !running { try await connect() }
        pendingControls.insert("authorization")
        observationRevision &+= 1
        let generation = generation
        publish(.init(connectionState: .authorizing, source: .spotify))
        defer {
            if self.generation == generation {
                pendingControls.remove("authorization")
                drainRefresh()
                scheduleFallback()
            }
        }
        await readPlayback(prompt: true)
    }
    public func openSpotify() async throws {
        try await controller.openSpotify()
        if !running { try await connect() }
        await refresh()
    }
    public func setExpandedVisible(_ visible: Bool) async {
        guard expandedVisible != visible, !Task.isCancelled else { return }
        expandedVisible = visible
        if visible { await refresh() }
    }
    public func refresh() async {
        guard running, !sleeping, !Task.isCancelled else { return }
        guard !playbackFetchInFlight, pendingControls.isEmpty else {
            refreshRequested = true
            return
        }
        playbackFetchInFlight = true
        let generation = generation
        await readPlayback()
        guard self.generation == generation else { return }
        playbackFetchInFlight = false
        drainRefresh()
        scheduleFallback()
    }
    private func readPlayback(prompt: Bool = false) async {
        let generation = generation
        observationRevision &+= 1
        let revision = observationRevision
        let started = ProcessInfo.processInfo.systemUptime
        do {
            var next = try await controller.read(prompt: prompt)
            guard !Task.isCancelled, running, !sleeping, self.generation == generation,
                  observationRevision == revision else { return }
            next.timestamp = await clock.now()
            guard !Task.isCancelled, self.generation == generation, observationRevision == revision else { return }
            next.observationStartedUptime = started
            next.sampledUptime = ProcessInfo.processInfo.systemUptime
            if next.localSpotifyStatus == .ready {
                guard reconciliation?.accepts(next, uptime: next.sampledUptime!) != false else { return }
            }
            reconciliation = nil
            publish(next)
        } catch {
            guard !Task.isCancelled, running, self.generation == generation, observationRevision == revision else { return }
            var next = state
            next.issue = "Spotify couldn’t refresh playback. Try again."
            if !next.hasMedia { next.connectionState = .error }
            publish(next)
        }
    }
    private func drainRefresh() {
        guard refreshRequested, running, !sleeping, pendingControls.isEmpty, !playbackFetchInFlight else { return }
        refreshRequested = false
        let generation = generation
        eventRefreshTask = Task { [weak self] in
            guard let self, await self.generation == generation, !Task.isCancelled else { return }
            await self.refresh()
        }
    }
    private func scheduleFallback() {
        pollTask?.cancel(); pollTask = nil
        // Notifications carry transport changes; periodic reads only correct drift/volume or
        // recover transient failures while the authorized desktop app is actually available.
        guard running, !sleeping, state.localSpotifyStatus == .ready || state.localSpotifyStatus == nil else { return }
        let generation = generation
        let delay: Duration = state.isPlaying ? .seconds(15) : .seconds(30)
        pollTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self, await self.generation == generation else { return }
            await self.fallbackFired()
        }
    }
    private func fallbackFired() async {
        pollTask = nil
        await refresh()
    }

    public func perform(_ command: MediaCommand) async throws {
        guard running, !sleeping else { throw MediaFailure.disconnected }
        guard !pendingControls.contains(command.controlID) else { throw MediaFailure.busy }
        pendingControls.insert(command.controlID)
        observationRevision &+= 1; inputRevision &+= 1
        reconciliationTask?.cancel(); reconciliationTask = nil
        let generation = generation
        let input = inputRevision
        let origin = state
        if let expectation = PlaybackReconciliation(command: command, origin: origin,
                                                     uptime: ProcessInfo.processInfo.systemUptime) {
            reconciliation = expectation
        }
        defer {
            if self.generation == generation {
                pendingControls.remove(command.controlID)
                if pendingControls.isEmpty {
                    if reconciliation != nil { scheduleReconciliation(generation: generation, input: inputRevision) }
                    drainRefresh()
                    scheduleFallback()
                }
            }
        }
        do {
            try await controller.perform(command, state: origin)
            guard !Task.isCancelled, self.generation == generation else { throw CancellationError() }
            observationRevision &+= 1
            // Drag writes stay lightweight. The session requests one real read on release.
            if case .setVolume = command { return }
            await readPlayback()
        } catch {
            if self.generation == generation, inputRevision == input {
                reconciliation = nil
                refreshRequested = true
            }
            throw error
        }
    }
    public func resumePlayback() async throws { try await perform(.play) }

    private func startEvents() {
        let generation = generation
        playbackEventsTask = Task { [weak self, playbackEvents] in
            for await event in await playbackEvents.events() {
                guard !Task.isCancelled, let self, await self.generation == generation else { return }
                await self.playbackChanged(event)
            }
        }
        lifecycleTask = Task { [weak self, lifecycleEvents] in
            for await event in await lifecycleEvents.events() {
                guard !Task.isCancelled, let self, await self.generation == generation else { return }
                await self.lifecycleChanged(event)
            }
        }
    }
    private func playbackChanged(_ event: SpotifyPlaybackEvent) async {
        guard running, !sleeping else { return }
        observationRevision &+= 1
        // Desktop notifications are refresh hints, never authoritative playback metadata.
        if reconciliation?.preservesSeek(through: event, uptime: ProcessInfo.processInfo.systemUptime) != true,
           reconciliation == nil {
            reconciliation = .init(origin: state, target: .event(event),
                                   startedAt: ProcessInfo.processInfo.systemUptime)
        }
        await refresh()
        if reconciliation != nil { scheduleReconciliation(generation: generation, input: inputRevision) }
    }
    private func lifecycleChanged(_ event: SpotifyLifecycleEvent) async {
        observationRevision &+= 1
        reconciliation = nil
        reconciliationTask?.cancel(); reconciliationTask = nil
        pollTask?.cancel(); pollTask = nil
        if event == .sleep {
            sleeping = true
            return
        }
        sleeping = false
        await refresh()
    }
    private func scheduleReconciliation(generation: Int, input: Int) {
        reconciliationTask?.cancel()
        reconciliationTask = Task { [weak self, clock] in
            for delay in [Duration.milliseconds(250), .milliseconds(500), .seconds(1)] {
                do { try await clock.sleep(for: delay) } catch { return }
                guard !Task.isCancelled, let self, await self.generation == generation,
                      await self.inputRevision == input, await self.reconciliation != nil else { return }
                await self.refresh()
            }
        }
    }
}
