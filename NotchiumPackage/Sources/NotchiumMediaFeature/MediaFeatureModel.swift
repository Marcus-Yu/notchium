import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import OSLog
import SwiftUI

@MainActor @Observable
public final class MediaSessionController {
    #if DEBUG
    private static let performanceLogger = Logger(subsystem: "com.marcusyu.notchium", category: "media-performance")
    #endif
    private static let previousTrackThreshold: TimeInterval = 3
    private static let reconciliationGrace: TimeInterval = 10
    private static let visibleQueueRefreshInterval = Duration.seconds(5)
    private static let playbackActivityRefreshCooldown = Duration.seconds(2)
    private static let volumeThrottleInterval = Duration.milliseconds(120)

    public let audioMeter: SystemAudioMeter
    public private(set) var collapsedMediaVisible = false
    public private(set) var isShowingCachedTrack = false
    @ObservationIgnored private let visibilityClock: any AppClock
    @ObservationIgnored private let controlClock: any AppClock
    @ObservationIgnored private let snapshotStore: any MediaSnapshotStoring
    public private(set) var state = MediaState(availability: .unavailable(.permissionNotDetermined),
                                               connectionState: .initializing, source: .spotify)
    private var authoritativeState = MediaState(availability: .unavailable(.permissionNotDetermined),
                                                connectionState: .initializing, source: .spotify)
    public private(set) var errorMessage: String?
    public private(set) var devices: [SpotifyDevice] = []
    public private(set) var devicesLoading = false
    public private(set) var deviceIssue: String?
    public private(set) var pendingControls: Set<String> = []
    public var isBusy: Bool { !pendingControls.isEmpty }
    public func isPending(_ command: MediaCommand) -> Bool { pendingControls.contains(command.controlID) }
    public var isPreviousPending: Bool { isPending(.previous) || isPending(.seek(0)) }
    public private(set) var lastSeekTarget: Double?
    public private(set) var seekInFlight = false
    @ObservationIgnored private var provider: any MediaProviding
    @ObservationIgnored private let coordinator: ActivityCoordinator
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var commandTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var queueTask: Task<Void, Never>?
    @ObservationIgnored private var visibleQueueTask: Task<Void, Never>?
    @ObservationIgnored private var playbackActivityRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var devicesTask: Task<Void, Never>?
    @ObservationIgnored private var volumeThrottleTask: Task<Void, Never>?
    @ObservationIgnored private var volumeCommandTask: Task<Void, Never>?
    @ObservationIgnored private var cacheLoadTask: Task<Void, Never>?
    @ObservationIgnored private var cacheWriteTask: Task<Void, Never>?
    @ObservationIgnored private var queuedVolumeRequest: VolumeRequest?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var intentRevision = 0
    private var pendingShuffleIntent: PendingMediaValue<Bool>?
    private var pendingRepeatIntent: PendingMediaValue<MediaRepeatMode>?
    private var pendingVolumeIntent: PendingMediaValue<Int>?
    // A timestamp barrier rejects already-buffered pre-action samples, never future observations.
    // Track/progress reconciliation belongs entirely to the provider.
    @ObservationIgnored private var playbackAction: (date: Date, uptime: TimeInterval, revision: Int)?
    private var lastCachedTrack: CachedMediaTrack?
    private var isUpNextVisible = false
    private let activityID = UUID()

    public init(
        provider: any MediaProviding,
        coordinator: ActivityCoordinator,
        visibilityClock: any AppClock = ContinuousAppClock(),
        controlClock: any AppClock = ContinuousAppClock(),
        snapshotStore: any MediaSnapshotStoring = NoopMediaSnapshotStore(),
        audioMeter: SystemAudioMeter = SystemAudioMeter(captureEnabled: false)
    ) {
        self.audioMeter = audioMeter
        self.provider = provider
        self.coordinator = coordinator
        self.visibilityClock = visibilityClock
        self.controlClock = controlClock
        self.snapshotStore = snapshotStore
        audioMeter.setPlaybackActivityHandler { [weak self] in self?.spotifyAudioBecameActive() }
        audioMeter.setLocalAudioActivityHandler { [weak self] _ in
            guard let self else { return }
            self.updateCollapsedVisibility(self.state)
        }
    }
    deinit {
        observation?.cancel()
        commandTasks.values.forEach { $0.cancel() }
        queueTask?.cancel()
        visibleQueueTask?.cancel()
        playbackActivityRefreshTask?.cancel()
        devicesTask?.cancel()
        volumeThrottleTask?.cancel()
        volumeCommandTask?.cancel()
        cacheLoadTask?.cancel()
        cacheWriteTask?.cancel()
    }
    public func start() {
        guard observation == nil else { return }
        restoreCachedTrack()
        let generation = generation
        let provider = provider
        observation = Task { [weak self] in
            for await value in await provider.updates() {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.receive(value)
            }
        }
    }
    public func stop() {
        audioMeter.stop()
        collapsedMediaVisible = false
        generation &+= 1; observation?.cancel(); observation = nil
        commandTasks.values.forEach { $0.cancel() }; commandTasks.removeAll(); pendingControls.removeAll()
        queueTask?.cancel(); queueTask = nil
        visibleQueueTask?.cancel(); visibleQueueTask = nil; isUpNextVisible = false
        audioMeter.setWaveformPresentationEnabled(true)
        playbackActivityRefreshTask?.cancel(); playbackActivityRefreshTask = nil
        devicesTask?.cancel(); devicesTask = nil; devices = []; devicesLoading = false; deviceIssue = nil
        volumeThrottleTask?.cancel(); volumeThrottleTask = nil
        volumeCommandTask?.cancel(); volumeCommandTask = nil; queuedVolumeRequest = nil
        cacheLoadTask?.cancel(); cacheLoadTask = nil
        coordinator.dismiss(id: activityID)
        authoritativeState = .init()
        state = .init(); isShowingCachedTrack = false; clearPendingSeek(); clearOptimisticIntents()
        seekInFlight = false
    }
    public func use(_ provider: any MediaProviding) {
        stop(); self.provider = provider; errorMessage = nil; start()
    }
    /// Provider snapshots are the only input; activity identity stays stable across progress/track changes.
    public func receive(_ value: MediaState) {
        if let action = playbackAction {
            if let uptime = value.observationStartedUptime ?? value.sampledUptime {
                guard uptime >= action.uptime else { return }
            } else {
                guard value.timestamp >= action.date else { return }
            }
        }
        lastSeekTarget = nil
        let previous = state
        let previousConnectionState = authoritativeState.connectionState
        authoritativeState = value
        let reconciled = applyingControlFeedback(to: value)
        let (next, showingCachedTrack) = presentationState(for: reconciled)
        if previousConnectionState == value.connectionState,
           isUnchangedPausedPresentation(next, showingCachedTrack: showingCachedTrack) { return }
        applyPresentation(next, showingCachedTrack: showingCachedTrack)
        if previous.activeDeviceID != next.activeDeviceID {
            devices = devices.map {
                .init(id: $0.id, name: $0.name, type: $0.type,
                      isActive: $0.id == next.activeDeviceID, isRestricted: $0.isRestricted,
                      volumePercent: $0.volumePercent, supportsVolume: $0.supportsVolume)
            }
        }
        if isUpNextVisible, previous.trackID != next.trackID, next.source == .spotify,
           next.capabilities.canReadQueue, !isPending(.next), !isPending(.previous) {
            scheduleQueueRefresh()
        }
    }

    private func isUnchangedPausedPresentation(_ next: MediaState, showingCachedTrack: Bool) -> Bool {
        guard !next.isPlaying, isShowingCachedTrack == showingCachedTrack,
              pendingShuffleIntent == nil, pendingRepeatIntent == nil,
              pendingVolumeIntent == nil else { return false }
        var comparable = next
        comparable.timestamp = state.timestamp
        comparable.sampledUptime = state.sampledUptime
        comparable.observationStartedUptime = state.observationStartedUptime
        return comparable == state
    }

    private func presentationState(for value: MediaState) -> (MediaState, Bool) {
        if let cached = CachedMediaTrack(state: value) {
            cache(cached)
            return (value, false)
        }
        guard let lastCachedTrack else { return (value, false) }
        let paused = lastCachedTrack.pausedPresentation(issue: value.issue)
        return (paused, true)
    }

    private func cache(_ track: CachedMediaTrack) {
        guard lastCachedTrack != track else { return }
        lastCachedTrack = track
        let store = snapshotStore
        cacheWriteTask?.cancel()
        cacheWriteTask = Task { await store.saveLastMediaTrack(track) }
    }

    private func restoreCachedTrack() {
        guard cacheLoadTask == nil, lastCachedTrack == nil else { return }
        let store = snapshotStore
        let generation = generation
        cacheLoadTask = Task { [weak self] in
            let cached = await store.loadLastMediaTrack()
            guard let self, self.generation == generation, let cached else { return }
            self.cacheLoadTask = nil
            guard self.lastCachedTrack == nil else { return }
            self.lastCachedTrack = cached
            guard !self.authoritativeState.hasMedia else { return }
            let paused = cached.pausedPresentation(issue: self.authoritativeState.issue)
            self.applyPresentation(paused, showingCachedTrack: true)
        }
    }

    private func applyingControlFeedback(to value: MediaState) -> MediaState {
        var next = value

        if let intent = pendingShuffleIntent {
            if value.shuffle == intent.value {
                pendingShuffleIntent = nil
            } else if intent.shouldHold(value.timestamp, grace: Self.reconciliationGrace) {
                next.shuffle = intent.value
            } else {
                pendingShuffleIntent = nil
            }
        }
        if let intent = pendingRepeatIntent {
            if value.repeatMode == intent.value {
                pendingRepeatIntent = nil
            } else if intent.shouldHold(value.timestamp, grace: Self.reconciliationGrace) {
                next.repeatMode = intent.value
            } else {
                pendingRepeatIntent = nil
            }
        }
        if let intent = pendingVolumeIntent {
            if value.volumePercent == intent.value {
                pendingVolumeIntent = nil
            } else if intent.shouldHold(value.timestamp, grace: Self.reconciliationGrace) {
                next.volumePercent = intent.value
            } else {
                pendingVolumeIntent = nil
            }
        }
        return next
    }

    private func applyPresentation(_ next: MediaState, showingCachedTrack: Bool? = nil) {
        if state.activeDeviceID != next.activeDeviceID {
            audioMeter.resetLocalAudioActivity()
        }
        if state != next { state = next }
        if let showingCachedTrack, isShowingCachedTrack != showingCachedTrack {
            isShowingCachedTrack = showingCachedTrack
        }
        // Capture lifecycle follows live provider connectivity, never the cached presentation.
        audioMeter.setMonitoringPlaybackActivity(authoritativeState.connectionState == .authenticated)
        audioMeter.setPlaying(next.hasMedia && next.isPlaying)
        updateCollapsedVisibility(next)
        if errorMessage != next.issue { errorMessage = next.issue }
        if next.hasMedia {
            coordinator.present(.init(id: activityID, kind: .media, title: "Media",
                                      subtitle: nil, priority: .low,
                                      presentationStyle: .mediaSides,
                                      lifetime: .persistent,
                                      isDismissible: false,
                                      destination: .music,
                                      duration: nil))
        } else { coordinator.dismiss(id: activityID) }
    }
    private func updateCollapsedVisibility(_ value: MediaState) {
        let isVisible = value.hasMedia && value.isPlaying && audioMeter.isAudioActive
        guard collapsedMediaVisible != isVisible else { return }
        withAnimation(.easeInOut(duration: 0.12)) { collapsedMediaVisible = isVisible }
    }
    public func displayedPosition(at now: Date, uptime: TimeInterval? = nil) -> Double {
        estimatedPlaybackPosition(at: now, state: state, uptime: uptime)
    }
    public func seek(to position: Double, at now: Date = Date()) async throws {
        let request = try prepareSeek(to: position, at: now)
        try await executeSeek(request)
    }
    public func previous(at date: Date? = nil) {
        guard !isPreviousPending, state.hasMedia, state.canSkipBackward else { return }
        let now = date ?? Date()
        let position = displayedPosition(at: now, uptime: date == nil ? ProcessInfo.processInfo.systemUptime : nil)
        if position > Self.previousTrackThreshold {
            guard state.canSeek else {
                errorMessage = MediaFailure.unsupported.errorDescription
                return
            }
            startSeek(to: 0, at: now, refreshQueueAfterSuccess: true)
        } else {
            dispatch(.previous)
        }
    }
    public func send(_ command: MediaCommand) {
        if command == .previous {
            previous()
            return
        }
        if case .seek(let position) = command {
            startSeek(to: position)
            return
        }
        if case .setVolume(let value) = command {
            setVolume(value, final: true)
            return
        }
        dispatch(command)
    }

    /// Applies volume locally for every pointer update while serializing Spotify requests.
    public func setVolume(_ value: Double, final: Bool) {
        guard state.hasMedia, state.capabilities.canSetVolume, value.isFinite else { return }
        let target = min(max(value, 0), 1)
        intentRevision &+= 1
        let request = VolumeRequest(value: target, revision: intentRevision, final: final)
        applyOptimistic(.setVolume(target), revision: request.revision, at: Date())
        queuedVolumeRequest = request

        if final {
            volumeThrottleTask?.cancel()
            volumeThrottleTask = nil
            flushVolumeIfPossible()
        } else {
            scheduleVolumeFlush()
        }
    }

    private func scheduleVolumeFlush() {
        guard queuedVolumeRequest != nil, volumeCommandTask == nil, volumeThrottleTask == nil else { return }
        let clock = controlClock
        let generation = generation
        volumeThrottleTask = Task { [weak self] in
            do { try await clock.sleep(for: Self.volumeThrottleInterval) }
            catch { return }
            guard let self, self.generation == generation, !Task.isCancelled else { return }
            self.volumeThrottleTask = nil
            self.flushVolumeIfPossible()
        }
    }

    private func flushVolumeIfPossible() {
        guard volumeCommandTask == nil, let request = queuedVolumeRequest else { return }
        queuedVolumeRequest = nil
        pendingControls.insert(MediaCommand.setVolume(request.value).controlID)
        let provider = provider
        let generation = generation

        volumeCommandTask = Task { [weak self] in
            do {
                try await provider.perform(.setVolume(request.value))
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.errorMessage = nil
                self.completeVolumeRequest(request)
            } catch {
                await provider.refresh()
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.clearOptimisticIntent(for: .setVolume(request.value), revision: request.revision)
                let base = (self.playbackAction?.revision ?? request.revision) > request.revision
                    ? self.state : self.authoritativeState
                let reconciled = self.applyingControlFeedback(to: base)
                let (presentation, showingCachedTrack) = self.presentationState(for: reconciled)
                self.applyPresentation(presentation, showingCachedTrack: showingCachedTrack)
                self.errorMessage = (error as? MediaFailure)?.errorDescription ?? "Playback command failed."
                self.completeVolumeRequest(request)
            }
        }
    }

    private func completeVolumeRequest(_ request: VolumeRequest) {
        volumeCommandTask = nil

        if let queuedVolumeRequest {
            if queuedVolumeRequest.final {
                flushVolumeIfPossible()
            } else {
                scheduleVolumeFlush()
            }
        } else {
            pendingControls.remove(MediaCommand.setVolume(request.value).controlID)
        }
    }
    private func dispatch(_ command: MediaCommand) {
        guard !isPending(command), state.hasMedia, state.capabilities.supports(command) else { return }
        #if DEBUG
        let inputStartedAt = ProcessInfo.processInfo.systemUptime
        #endif
        let id = command.controlID
        pendingControls.insert(id)
        let provider = provider
        let generation = generation
        // Resolve toggle intent at the tap, before any asynchronous provider work.
        let resolved: MediaCommand = command == .playPause ? (state.isPlaying ? .pause : .play) : command
        intentRevision &+= 1
        let revision = intentRevision
        applyOptimistic(resolved, revision: revision, at: Date())
        #if DEBUG
        Self.performanceLogger.debug("[MediaInput] \(id, privacy: .public) local_ms=\((ProcessInfo.processInfo.systemUptime - inputStartedAt) * 1000)")
        #endif
        commandTasks[id] = Task { [weak self] in
            defer {
                if let self, self.generation == generation {
                    self.pendingControls.remove(id)
                    self.commandTasks[id] = nil
                }
            }
            do {
                switch resolved {
                case .play: try await provider.resumePlayback()
                case .pause: try await provider.pause()
                case .next: try await provider.nextTrack()
                case .previous: try await provider.previousTrack()
                case .seek(let position): try await provider.seek(to: position)
                case .setShuffle(let enabled): try await provider.setShuffle(enabled)
                case .setRepeatMode(let mode): try await provider.setRepeatMode(mode)
                default: try await provider.perform(resolved)
                }
                guard let self, self.generation == generation else { return }
                self.errorMessage = nil
                #if DEBUG
                Self.performanceLogger.debug("[MediaInput] \(id, privacy: .public) confirmed_ms=\((ProcessInfo.processInfo.systemUptime - inputStartedAt) * 1000)")
                #endif
                if self.isUpNextVisible && (resolved == .next || resolved == .previous) {
                    try? await provider.refreshQueue()
                }
            } catch {
                guard let self, self.generation == generation else { return }
                self.clearOptimisticIntent(for: resolved, revision: revision)
                // Failure of an older control must not undo newer immediate feedback.
                if (self.playbackAction?.revision ?? revision) <= revision {
                    let reconciled = self.applyingControlFeedback(to: self.authoritativeState)
                    let (presentation, showingCachedTrack) = self.presentationState(for: reconciled)
                    self.applyPresentation(presentation, showingCachedTrack: showingCachedTrack)
                }
                let message = (error as? MediaFailure)?.errorDescription ?? "Playback command failed."
                self.errorMessage = message
                #if DEBUG
                print("Media command \(id): \(message)")
                #endif
                await provider.refresh()
            }
        }
    }

    private func markPlaybackAction(at date: Date, revision: Int) {
        lastSeekTarget = nil
        playbackAction = (date, ProcessInfo.processInfo.systemUptime, revision)
    }

    private func applyOptimistic(_ command: MediaCommand, revision: Int, at now: Date) {
        var next = state
        switch command {
        case .play:
            next.elapsed = displayedPosition(at: now)
            next.timestamp = now
            next.playbackState = .playing
            next.playbackRate = 1
            next.sampledUptime = ProcessInfo.processInfo.systemUptime
            markPlaybackAction(at: now, revision: revision)
        case .pause:
            next.elapsed = displayedPosition(at: now)
            next.timestamp = now
            next.playbackState = .paused
            next.playbackRate = 0
            next.sampledUptime = ProcessInfo.processInfo.systemUptime
            markPlaybackAction(at: now, revision: revision)
        case .setShuffle(let enabled):
            next.shuffle = enabled
            pendingShuffleIntent = .init(value: enabled, requestedAt: now, revision: revision)
        case .setRepeatMode(let mode):
            next.repeatMode = mode
            pendingRepeatIntent = .init(value: mode, requestedAt: now, revision: revision)
        case .setVolume(let value):
            let percent = Int((min(max(value, 0), 1) * 100).rounded())
            next.volumePercent = percent
            pendingVolumeIntent = .init(value: percent, requestedAt: now, revision: revision)
        case .next, .previous:
            markPlaybackAction(at: now, revision: revision)
        default:
            break
        }
        applyPresentation(next)
    }

    private func clearOptimisticIntent(for command: MediaCommand, revision: Int) {
        if playbackAction?.revision == revision { playbackAction = nil }
        switch command {
        case .play, .pause, .playPause:
            break
        case .setShuffle, .toggleShuffle:
            if pendingShuffleIntent?.revision == revision { pendingShuffleIntent = nil }
        case .setRepeatMode, .cycleRepeat:
            if pendingRepeatIntent?.revision == revision { pendingRepeatIntent = nil }
        case .setVolume:
            if pendingVolumeIntent?.revision == revision { pendingVolumeIntent = nil }
        case .next, .previous:
            break
        default:
            break
        }
    }
    public func loadQueue() async {
        if let queueTask {
            await queueTask.value
            return
        }
        try? await provider.refreshQueue()
    }
    public func addToQueue(uri: String) async throws {
        try await provider.addToQueue(uri: uri)
    }
    public func refreshPlaybackState() async {
        await provider.refresh()
    }
    public func setExpandedVisible(_ visible: Bool) async {
        guard !Task.isCancelled else { return }
        await provider.setExpandedVisible(visible)
    }

    public func refreshDevices() {
        devicesTask?.cancel()
        devicesLoading = true
        deviceIssue = nil
        let provider = provider
        let generation = generation
        devicesTask = Task { [weak self] in
            do {
                let devices = try await provider.devices()
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.devices = devices
                self.devicesLoading = false
                self.devicesTask = nil
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.devices = []
                self.devicesLoading = false
                self.deviceIssue = "Devices unavailable"
                self.devicesTask = nil
            }
        }
    }

    public func transferPlayback(to device: SpotifyDevice) {
        guard !device.isRestricted, device.id != state.activeDeviceID else { return }
        let provider = provider
        let generation = generation
        devicesLoading = true
        deviceIssue = nil
        devicesTask?.cancel()
        devicesTask = Task { [weak self] in
            do {
                try await provider.transferPlayback(to: device.id)
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                // Device identity arrives in the same authoritative snapshot as playback.
                self.devicesLoading = false
                self.devicesTask = nil
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.devicesLoading = false
                self.deviceIssue = "Couldn’t connect to that device"
                self.devicesTask = nil
            }
        }
    }

    private struct VolumeRequest {
        let value: Double
        let revision: Int
        let final: Bool
    }

    private struct SeekRequest {
        let target: Double
        let generation: Int
        let refreshQueueAfterSuccess: Bool
        let revision: Int
    }
    private func prepareSeek(to position: Double, at now: Date,
                             refreshQueueAfterSuccess: Bool = false) throws -> SeekRequest {
        guard !seekInFlight, !isPending(.seek(position)) else { throw MediaFailure.busy }
        guard state.canSeek, position.isFinite, let duration = state.validDuration else {
            throw MediaFailure.unsupported
        }
        let target = min(max(position, 0), duration)
        let origin = state
        intentRevision &+= 1
        markPlaybackAction(at: now, revision: intentRevision)
        lastSeekTarget = target
        seekInFlight = true
        pendingControls.insert(MediaCommand.seek(target).controlID)

        // Immediate feedback modifies one snapshot/clock. The next authoritative observation
        // replaces it wholesale; there is no presentation-side seek/track confirmation machine.
        var next = origin
        next.elapsed = target
        next.timestamp = now
        next.sampledUptime = ProcessInfo.processInfo.systemUptime
        applyPresentation(next)
        return .init(target: target, generation: generation,
                     refreshQueueAfterSuccess: refreshQueueAfterSuccess, revision: intentRevision)
    }
    private func executeSeek(_ request: SeekRequest) async throws {
        let id = MediaCommand.seek(request.target).controlID
        let provider = provider
        defer {
            if generation == request.generation {
                pendingControls.remove(id)
                commandTasks[id] = nil
                seekInFlight = false
            }
        }
        do {
            try await provider.seek(to: request.target)
            if request.refreshQueueAfterSuccess && isUpNextVisible {
                try? await provider.refreshQueue()
            }
            guard generation == request.generation else { return }
            errorMessage = nil
        } catch {
            await provider.refresh()
            guard generation == request.generation else { throw error }
            if playbackAction?.revision == request.revision { playbackAction = nil }
            clearPendingSeek()
            if (playbackAction?.revision ?? request.revision) <= request.revision {
                applyPresentation(applyingControlFeedback(to: authoritativeState))
            }
            errorMessage = (error as? MediaFailure)?.errorDescription ?? "Playback command failed."
            throw error
        }
    }
    private func startSeek(to position: Double, at now: Date = Date(),
                           refreshQueueAfterSuccess: Bool = false) {
        guard let request = try? prepareSeek(to: position, at: now,
                                             refreshQueueAfterSuccess: refreshQueueAfterSuccess) else { return }
        let id = MediaCommand.seek(request.target).controlID
        commandTasks[id] = Task { [weak self] in
            do { try await self?.executeSeek(request) }
            catch {
                #if DEBUG
                print("Media command \(id): \((error as? MediaFailure)?.errorDescription ?? "Playback command failed.")")
                #endif
            }
        }
    }
    private func clearPendingSeek() {
        lastSeekTarget = nil
    }
    private func scheduleQueueRefresh() {
        guard queueTask == nil else { return }
        let provider = provider
        let generation = generation
        queueTask = Task { [weak self] in
            try? await provider.refreshQueue()
            guard let self, self.generation == generation else { return }
            self.queueTask = nil
        }
    }

    public func setUpNextVisible(_ visible: Bool) {
        guard isUpNextVisible != visible else { return }
        isUpNextVisible = visible
        audioMeter.setWaveformPresentationEnabled(!visible)
        visibleQueueTask?.cancel()
        visibleQueueTask = nil
        guard visible else { return }
        let provider = provider
        let generation = generation
        let clock = visibilityClock
        visibleQueueTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await provider.refreshQueue()
                do { try await clock.sleep(for: Self.visibleQueueRefreshInterval) }
                catch { return }
                guard let self, self.generation == generation, self.isUpNextVisible else { return }
            }
        }
    }

    private func spotifyAudioBecameActive() {
        guard state.connectionState == .authenticated, !state.isPlaying,
              playbackActivityRefreshTask == nil else { return }
        let provider = provider
        let generation = generation
        let clock = visibilityClock
        playbackActivityRefreshTask = Task { [weak self] in
            await provider.refresh()
            do { try await clock.sleep(for: Self.playbackActivityRefreshCooldown) }
            catch { return }
            guard let self, self.generation == generation else { return }
            self.playbackActivityRefreshTask = nil
        }
    }

    private func clearOptimisticIntents() {
        pendingShuffleIntent = nil
        pendingRepeatIntent = nil
        pendingVolumeIntent = nil
        playbackAction = nil
    }
}

private struct PendingMediaValue<Value: Equatable> {
    let value: Value
    let requestedAt: Date
    let revision: Int

    func shouldHold(_ observedAt: Date, grace: TimeInterval) -> Bool {
        observedAt.timeIntervalSince(requestedAt) < grace
    }
}

/// Retains the existing feature-facing name for the app-owned session controller.
public typealias MediaFeatureModel = MediaSessionController
