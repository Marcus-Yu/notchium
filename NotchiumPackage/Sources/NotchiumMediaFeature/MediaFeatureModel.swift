import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import SwiftUI

@MainActor @Observable
public final class MediaSessionController {
    private static let previousTrackThreshold: TimeInterval = 3

    public let audioMeter: SystemAudioMeter
    public private(set) var collapsedMediaVisible = false
    @ObservationIgnored private var mediaHideTask: Task<Void, Never>?
    @ObservationIgnored private let visibilityClock: any AppClock
    public private(set) var state = MediaState(availability: .unavailable(.permissionNotDetermined),
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
    @ObservationIgnored private var generation = 0
    private let activityID = UUID()

    public init(provider: any MediaProviding, coordinator: ActivityCoordinator, visibilityClock: any AppClock = ContinuousAppClock(), audioMeter: SystemAudioMeter = SystemAudioMeter(captureEnabled: false)) {
        self.audioMeter = audioMeter
        self.provider = provider; self.coordinator = coordinator; self.visibilityClock = visibilityClock
    }
    deinit {
        observation?.cancel()
        commandTasks.values.forEach { $0.cancel() }
        queueTask?.cancel()
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
        coordinator.dismiss(id: activityID)
        state = .init(); clearPendingSeek()
    }
    public func use(_ provider: any MediaProviding) {
        stop(); self.provider = provider; errorMessage = nil; start()
    }
    /// Provider snapshots are the only input; activity identity stays stable across progress/track changes.
    public func receive(_ value: MediaState) {
        let previous = state
        var next = value
        if let pendingSeek {
            if pendingSeek.accepts(value) {
                clearPendingSeek()
            } else {
                // Spotify may briefly return the pre-seek position. Preserve all other provider fields,
                // but do not let that stale progress become the authoritative presentation sample.
                next.elapsed = previous.elapsed
                next.timestamp = previous.timestamp
                next.playbackRate = previous.playbackRate
            }
        }
        audioMeter.setPlaying(next.hasMedia && next.isPlaying)
        updateCollapsedVisibility(next)
        state = next
        errorMessage = next.issue
        if next.hasMedia {
            coordinator.present(.init(id: activityID, kind: .media, title: "Media",
                                      subtitle: nil, priority: 20, duration: nil))
        } else { coordinator.dismiss(id: activityID) }
        if previous.trackID != next.trackID, next.source == .spotify,
           next.capabilities.canReadQueue, !isPending(.next), !isPending(.previous) {
            scheduleQueueRefresh()
        }
    }
    private func updateCollapsedVisibility(_ value: MediaState) {
        if value.hasMedia && value.isPlaying {
            mediaHideTask?.cancel(); mediaHideTask = nil
            withAnimation(.easeInOut(duration: 0.12)) { collapsedMediaVisible = true }
        } else if !value.hasMedia {
            audioMeter.stop()
            mediaHideTask?.cancel(); mediaHideTask = nil
            withAnimation(.easeInOut(duration: 0.12)) { collapsedMediaVisible = false }
        } else if collapsedMediaVisible && mediaHideTask == nil {
            mediaHideTask = Task { [weak self, visibilityClock] in
                do { try await visibilityClock.sleep(for: .milliseconds(450)) } catch { return }
                guard !Task.isCancelled, let self, !self.state.isPlaying else { return }
                withAnimation(.easeInOut(duration: 0.12)) { self.collapsedMediaVisible = false }
                self.audioMeter.stop()
                self.mediaHideTask = nil
            }
        }
    }
    public func displayedPosition(at now: Date) -> Double {
        lastSeekTarget ?? estimatedPlaybackPosition(at: now, state: state)
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
                    try? await provider.loadQueue()
                }
            } catch {
                guard let self, self.generation == generation else { return }
                let message = (error as? MediaFailure)?.errorDescription ?? "Playback command failed."
                self.errorMessage = message
                #if DEBUG
                print("Media command \(id): \(message)")
                #endif
                await provider.refresh()
            }
        }
    }
    public func loadQueue() async {
        if let queueTask {
            await queueTask.value
            return
        }
        try? await provider.loadQueue()
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
        pendingSeek = PendingMediaSeek(position: target, requestedAt: now, origin: state)
        lastSeekTarget = target
        seekInFlight = true
        pendingControls.insert(MediaCommand.seek(target).controlID)
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
            if request.refreshQueueAfterSuccess { try? await provider.loadQueue() }
            guard generation == request.generation else { return }
            errorMessage = nil
        } catch {
            await provider.refresh()
            guard generation == request.generation else { throw error }
            clearPendingSeek()
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
            try? await provider.loadQueue()
            guard let self, self.generation == generation else { return }
            self.queueTask = nil
        }
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
}

/// Retains the existing feature-facing name for the app-owned session controller.
public typealias MediaFeatureModel = MediaSessionController
