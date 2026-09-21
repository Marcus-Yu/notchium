import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import SwiftUI

@MainActor @Observable
public final class MediaSessionController {
    private static let previousTrackThreshold: TimeInterval = 3
    private static let reconciliationGrace: TimeInterval = 10
    private static let visibleQueueRefreshInterval = Duration.seconds(5)
    private static let playbackActivityRefreshCooldown = Duration.seconds(2)

    public let audioMeter: SystemAudioMeter
    public private(set) var collapsedMediaVisible = false
    @ObservationIgnored private var mediaHideTask: Task<Void, Never>?
    @ObservationIgnored private let visibilityClock: any AppClock
    public private(set) var state = MediaState(availability: .unavailable(.permissionNotDetermined),
                                               connectionState: .initializing, source: .spotify)
    private var authoritativeState = MediaState(availability: .unavailable(.permissionNotDetermined),
                                                connectionState: .initializing, source: .spotify)
    public private(set) var errorMessage: String?
    public private(set) var pendingControls: Set<String> = []
    public var isBusy: Bool { !pendingControls.isEmpty }
    public func isPending(_ command: MediaCommand) -> Bool { pendingControls.contains(command.controlID) }
    public var isPreviousPending: Bool { isPending(.previous) || isPending(.seek(0)) }
    public private(set) var pendingSeek: PendingMediaSeek?
    public private(set) var lastSeekTarget: Double?
    public private(set) var seekInFlight = false
    @ObservationIgnored private var provider: any MediaProviding
    @ObservationIgnored private let coordinator: ActivityCoordinator
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var commandTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var queueTask: Task<Void, Never>?
    @ObservationIgnored private var visibleQueueTask: Task<Void, Never>?
    @ObservationIgnored private var playbackActivityRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var intentRevision = 0
    private var pendingPlaybackIntent: PendingMediaValue<MediaPlaybackState>?
    private var pendingShuffleIntent: PendingMediaValue<Bool>?
    private var pendingRepeatIntent: PendingMediaValue<MediaRepeatMode>?
    private var pendingTrackTransition: PendingTrackTransition?
    private var isUpNextVisible = false
    private let activityID = UUID()

    public init(provider: any MediaProviding, coordinator: ActivityCoordinator, visibilityClock: any AppClock = ContinuousAppClock(), audioMeter: SystemAudioMeter = SystemAudioMeter(captureEnabled: false)) {
        self.audioMeter = audioMeter
        self.provider = provider; self.coordinator = coordinator; self.visibilityClock = visibilityClock
        audioMeter.setPlaybackActivityHandler { [weak self] in self?.spotifyAudioBecameActive() }
    }
    deinit {
        observation?.cancel()
        commandTasks.values.forEach { $0.cancel() }
        queueTask?.cancel()
        visibleQueueTask?.cancel()
        playbackActivityRefreshTask?.cancel()
        mediaHideTask?.cancel()
    }
    public func start() {
        guard observation == nil else { return }
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
        mediaHideTask?.cancel(); mediaHideTask = nil; collapsedMediaVisible = false
        generation &+= 1; observation?.cancel(); observation = nil
        commandTasks.values.forEach { $0.cancel() }; commandTasks.removeAll(); pendingControls.removeAll()
        queueTask?.cancel(); queueTask = nil
        visibleQueueTask?.cancel(); visibleQueueTask = nil; isUpNextVisible = false
        playbackActivityRefreshTask?.cancel(); playbackActivityRefreshTask = nil
        coordinator.dismiss(id: activityID)
        authoritativeState = .init()
        state = .init(); clearPendingSeek(); clearOptimisticIntents()
    }
    public func use(_ provider: any MediaProviding) {
        stop(); self.provider = provider; errorMessage = nil; start()
    }
    /// Provider snapshots are the only input; activity identity stays stable across progress/track changes.
    public func receive(_ value: MediaState) {
        let previous = state
        authoritativeState = value
        let next = reconcile(value, against: previous)
        applyPresentation(next)
        if previous.trackID != next.trackID, next.source == .spotify,
           next.capabilities.canReadQueue, !isPending(.next), !isPending(.previous) {
            scheduleQueueRefresh()
        }
    }

    private func reconcile(_ value: MediaState, against previous: MediaState) -> MediaState {
        var next = value

        if let transition = pendingTrackTransition {
            if value.hasMedia, !value.isSameTrack(as: transition.origin) {
                pendingTrackTransition = nil
            } else if transition.shouldHold(value) {
                next = value.preservingMedia(from: previous)
            } else {
                pendingTrackTransition = nil
            }
        }

        if let pendingSeek {
            if pendingSeek.accepts(value) {
                clearPendingSeek()
            } else {
                // Spotify may briefly return the pre-seek position. Preserve all other provider fields,
                // but do not let that stale progress become the authoritative presentation sample.
                next.elapsed = pendingSeek.position
                next.timestamp = pendingSeek.requestedAt
                next.playbackRate = pendingSeek.origin.isPlaying ? pendingSeek.origin.playbackRate : 0
            }
        }

        if let intent = pendingPlaybackIntent {
            if value.hasMedia, value.playbackState == intent.value {
                pendingPlaybackIntent = nil
            } else if intent.shouldHold(value.timestamp, grace: Self.reconciliationGrace) {
                next.playbackState = intent.value
                next.elapsed = previous.elapsed
                next.timestamp = previous.timestamp
                next.playbackRate = intent.value == .playing ? 1 : 0
            } else {
                pendingPlaybackIntent = nil
            }
        }
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
        return next
    }

    private func applyPresentation(_ next: MediaState) {
        audioMeter.setMonitoringPlaybackActivity(next.connectionState == .authenticated)
        audioMeter.setPlaying(next.hasMedia && next.isPlaying)
        updateCollapsedVisibility(next)
        state = next
        errorMessage = next.issue
        if next.hasMedia {
            coordinator.present(.init(id: activityID, kind: .media, title: "Media",
                                      subtitle: nil, priority: 20, duration: nil))
        } else { coordinator.dismiss(id: activityID) }
    }
    private func updateCollapsedVisibility(_ value: MediaState) {
        if value.hasMedia && value.isPlaying {
            mediaHideTask?.cancel(); mediaHideTask = nil
            withAnimation(.easeInOut(duration: 0.12)) { collapsedMediaVisible = true }
        } else if !value.hasMedia {
            mediaHideTask?.cancel(); mediaHideTask = nil
            withAnimation(.easeInOut(duration: 0.12)) { collapsedMediaVisible = false }
        } else if collapsedMediaVisible && mediaHideTask == nil {
            mediaHideTask = Task { [weak self, visibilityClock] in
                do { try await visibilityClock.sleep(for: .milliseconds(450)) } catch { return }
                guard !Task.isCancelled, let self, !self.state.isPlaying else { return }
                withAnimation(.easeInOut(duration: 0.12)) { self.collapsedMediaVisible = false }
                self.mediaHideTask = nil
            }
        }
    }
    public func displayedPosition(at now: Date) -> Double {
        pendingSeek?.displayedPosition(at: now, state: state)
            ?? estimatedPlaybackPosition(at: now, state: state)
    }
    public func seek(to position: Double, at now: Date = Date()) async throws {
        let request = try prepareSeek(to: position, at: now)
        try await executeSeek(request)
    }
    public func previous(at now: Date = Date()) {
        guard !isPreviousPending, state.hasMedia, state.canSkipBackward else { return }
        let position = displayedPosition(at: now)
        #if DEBUG
        print("[SpotifyControls] Previous pressed")
        print("[SpotifyControls] Current position: \(String(format: "%.1f", position))s")
        #endif
        if position > Self.previousTrackThreshold {
            guard state.canSeek else {
                errorMessage = MediaFailure.unsupported.errorDescription
                #if DEBUG
                print("[SpotifyControls] Cannot restart current track because seeking is unavailable")
                #endif
                return
            }
            #if DEBUG
            print("[SpotifyControls] Seeking current track to beginning")
            #endif
            startSeek(to: 0, at: now, refreshQueueAfterSuccess: true)
        } else {
            #if DEBUG
            print("[SpotifyControls] Requesting previous track")
            #endif
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
        dispatch(command)
    }
    private func dispatch(_ command: MediaCommand) {
        guard !isPending(command), state.hasMedia, state.capabilities.supports(command) else { return }
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
        switch resolved {
        case .play: print("[SpotifyControls] Play")
        case .pause: print("[SpotifyControls] Pause")
        case .next: print("[SpotifyControls] Next pressed")
        case .setShuffle(let enabled): print("[SpotifyControls] Shuffle → \(enabled ? "enabled" : "disabled")")
        case .setRepeatMode(let mode): print("[SpotifyControls] Repeat → \(mode.rawValue)")
        default: break
        }
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
                case .play: try await provider.play()
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
                if resolved == .next || resolved == .previous {
                    try? await provider.refreshQueue()
                }
            } catch {
                guard let self, self.generation == generation else { return }
                self.clearOptimisticIntent(for: resolved, revision: revision)
                let previous = self.state
                let reconciled = self.reconcile(self.authoritativeState, against: previous)
                self.applyPresentation(reconciled)
                let message = (error as? MediaFailure)?.errorDescription ?? "Playback command failed."
                self.errorMessage = message
                #if DEBUG
                print("Media command \(id): \(message)")
                #endif
                await provider.refresh()
            }
        }
    }

    private func applyOptimistic(_ command: MediaCommand, revision: Int, at now: Date) {
        var next = state
        switch command {
        case .play:
            next.elapsed = displayedPosition(at: now)
            next.timestamp = now
            next.playbackState = .playing
            next.playbackRate = 1
            pendingPlaybackIntent = .init(value: .playing, requestedAt: now, revision: revision)
        case .pause:
            next.elapsed = displayedPosition(at: now)
            next.timestamp = now
            next.playbackState = .paused
            next.playbackRate = 0
            pendingPlaybackIntent = .init(value: .paused, requestedAt: now, revision: revision)
        case .setShuffle(let enabled):
            next.shuffle = enabled
            pendingShuffleIntent = .init(value: enabled, requestedAt: now, revision: revision)
        case .setRepeatMode(let mode):
            next.repeatMode = mode
            pendingRepeatIntent = .init(value: mode, requestedAt: now, revision: revision)
        case .next, .previous:
            pendingTrackTransition = .init(origin: authoritativeState.hasMedia ? authoritativeState : state,
                                           requestedAt: now, revision: revision)
        default:
            break
        }
        applyPresentation(next)
    }

    private func clearOptimisticIntent(for command: MediaCommand, revision: Int) {
        switch command {
        case .play, .pause, .playPause:
            if pendingPlaybackIntent?.revision == revision { pendingPlaybackIntent = nil }
        case .setShuffle, .toggleShuffle:
            if pendingShuffleIntent?.revision == revision { pendingShuffleIntent = nil }
        case .setRepeatMode, .cycleRepeat:
            if pendingRepeatIntent?.revision == revision { pendingRepeatIntent = nil }
        case .next, .previous:
            if pendingTrackTransition?.revision == revision { pendingTrackTransition = nil }
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

    private struct SeekRequest {
        let target: Double
        let generation: Int
        let refreshQueueAfterSuccess: Bool
    }
    private func prepareSeek(to position: Double, at now: Date,
                             refreshQueueAfterSuccess: Bool = false) throws -> SeekRequest {
        guard !seekInFlight, !isPending(.seek(position)) else { throw MediaFailure.busy }
        guard state.canSeek, position.isFinite, let duration = state.validDuration else {
            throw MediaFailure.unsupported
        }
        let target = min(max(position, 0), duration)
        let origin = state
        pendingSeek = PendingMediaSeek(position: target, requestedAt: now, origin: origin)
        lastSeekTarget = target
        seekInFlight = true
        pendingControls.insert(MediaCommand.seek(target).controlID)

        // Rebase presentation atomically before starting the Spotify request. PendingMediaSeek
        // protects this new clock from responses that were sampled before the user action.
        var next = origin
        next.elapsed = target
        next.timestamp = now
        applyPresentation(next)
        return .init(target: target, generation: generation,
                     refreshQueueAfterSuccess: refreshQueueAfterSuccess)
    }
    private func executeSeek(_ request: SeekRequest) async throws {
        let id = MediaCommand.seek(request.target).controlID
        let provider = provider
        defer {
            if generation == request.generation {
                pendingControls.remove(id)
                commandTasks[id] = nil
            }
        }
        do {
            try await provider.seek(to: request.target)
            if request.refreshQueueAfterSuccess { try? await provider.refreshQueue() }
            guard generation == request.generation else { return }
            errorMessage = nil
        } catch {
            await provider.refresh()
            guard generation == request.generation else { throw error }
            clearPendingSeek()
            let previous = state
            let reconciled = reconcile(authoritativeState, against: previous)
            applyPresentation(reconciled)
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
        pendingSeek = nil
        lastSeekTarget = nil
        seekInFlight = false
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
        pendingPlaybackIntent = nil
        pendingShuffleIntent = nil
        pendingRepeatIntent = nil
        pendingTrackTransition = nil
    }
}

/// Local presentation intent, separate from authoritative provider state.
public struct PendingMediaSeek {
    public let position: Double
    let requestedAt: Date
    let origin: MediaState

    func accepts(_ update: MediaState) -> Bool {
        guard update.hasMedia, update.isSameTrack(as: origin) else { return true }
        guard update.timestamp >= requestedAt else { return false }
        let delta = update.timestamp.timeIntervalSince(requestedAt)
        let expected = min(position + (update.isPlaying ? delta * update.playbackRate : 0), update.validDuration ?? 0)
        // Ignore eventual-consistency responses still describing the pre-seek position.
        // A later authoritative sample wins even if another device sought elsewhere.
        return abs(update.elapsedTime - expected) <= 2 || delta >= 10
    }

    func displayedPosition(at now: Date, state: MediaState) -> Double {
        guard let duration = state.validDuration ?? origin.validDuration else { return 0 }
        let shouldAdvance = state.isPlaying && state.playbackRate.isFinite && state.playbackRate > 0
        let delta = shouldAdvance ? max(0, now.timeIntervalSince(requestedAt)) * state.playbackRate : 0
        return min(max(position + delta, 0), duration)
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

private struct PendingTrackTransition {
    let origin: MediaState
    let requestedAt: Date
    let revision: Int

    func shouldHold(_ update: MediaState) -> Bool {
        update.timestamp.timeIntervalSince(requestedAt) < 10
    }
}

private extension MediaState {
    func preservingMedia(from previous: MediaState) -> MediaState {
        var merged = self
        merged.playbackState = previous.playbackState
        merged.trackID = previous.trackID
        merged.activeDeviceID = previous.activeDeviceID
        merged.title = previous.title
        merged.artist = previous.artist
        merged.artwork = previous.artwork
        merged.source = previous.source
        merged.elapsed = previous.elapsed
        merged.duration = previous.duration
        merged.timestamp = previous.timestamp
        merged.playbackRate = previous.playbackRate
        merged.capabilities = previous.capabilities
        merged.shuffle = previous.shuffle
        merged.repeatMode = previous.repeatMode
        merged.queue = previous.queue
        merged.queueIssue = previous.queueIssue
        return merged
    }
}

/// Retains the existing feature-facing name for the app-owned session controller.
public typealias MediaFeatureModel = MediaSessionController
