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
    public private(set) var state = MediaState()
    public private(set) var errorMessage: String?
    public private(set) var pendingControls: Set<String> = []
    public var isBusy: Bool { !pendingControls.isEmpty }
    public func isPending(_ command: MediaCommand) -> Bool { pendingControls.contains(command.controlID) }
    public var isPreviousPending: Bool { isPending(.previous) || isPending(.seek(0)) }
    public private(set) var pendingSeek: PendingMediaSeek?
    @ObservationIgnored private var provider: any MediaProviding
    @ObservationIgnored private let coordinator: ActivityCoordinator
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var commandTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    private let activityID = UUID()

    public init(provider: any MediaProviding, coordinator: ActivityCoordinator, visibilityClock: any AppClock = ContinuousAppClock(), audioMeter: SystemAudioMeter = SystemAudioMeter(captureEnabled: false)) {
        self.audioMeter = audioMeter
        self.provider = provider; self.coordinator = coordinator; self.visibilityClock = visibilityClock
    }
    deinit { observation?.cancel(); commandTasks.values.forEach { $0.cancel() }; mediaHideTask?.cancel() }
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
        coordinator.dismiss(id: activityID)
        state = .init(); pendingSeek = nil
    }
    public func use(_ provider: any MediaProviding) {
        stop(); self.provider = provider; errorMessage = nil; start()
    }
    /// Provider snapshots are the only input; activity identity stays stable across progress/track changes.
    public func receive(_ value: MediaState) {
        if let pendingSeek, pendingSeek.accepts(value) { self.pendingSeek = nil }
        audioMeter.setPlaying(value.hasMedia && value.isPlaying)
        updateCollapsedVisibility(value)
        state = value
        errorMessage = value.issue
        if value.hasMedia {
            coordinator.present(.init(id: activityID, kind: .media, title: "Media",
                                      subtitle: nil, priority: 20, duration: nil))
        } else { coordinator.dismiss(id: activityID) }
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
        pendingSeek?.position ?? estimatedPlaybackPosition(at: now, state: state)
    }
    public func seek(to position: Double, at now: Date = Date()) {
        guard !isPending(.seek(position)), state.canSeek, position.isFinite else { return }
        pendingSeek = PendingMediaSeek(position: min(max(position, 0), state.validDuration ?? 0),
                                       requestedAt: now, origin: state)
        send(.seek(pendingSeek!.position))
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
            seek(to: 0, at: now)
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
            } catch {
                guard let self, self.generation == generation else { return }
                if case .seek = command { self.pendingSeek = nil }
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
        guard let real = provider as? RealMediaProvider else { return }
        do { try await real.loadQueue() }
        catch { errorMessage = (error as? MediaFailure)?.errorDescription ?? "Up Next is unavailable." }
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
        return abs(update.elapsedTime - expected) <= 3 || delta >= 10
    }
}

/// Retains the existing feature-facing name for the app-owned session controller.
public typealias MediaFeatureModel = MediaSessionController
