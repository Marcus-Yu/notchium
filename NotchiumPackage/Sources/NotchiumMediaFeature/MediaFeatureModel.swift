import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation

@MainActor @Observable
public final class MediaFeatureModel {
    public private(set) var state = MediaState()
    public private(set) var errorMessage: String?
    public private(set) var isBusy = false
    public private(set) var pendingSeek: PendingMediaSeek?
    @ObservationIgnored private var provider: any MediaProviding
    @ObservationIgnored private let coordinator: ActivityCoordinator
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    private let activityID = UUID()

    public init(provider: any MediaProviding, coordinator: ActivityCoordinator) {
        self.provider = provider; self.coordinator = coordinator
    }
    deinit { observation?.cancel(); commandTask?.cancel() }
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
        generation &+= 1; observation?.cancel(); observation = nil
        commandTask?.cancel(); commandTask = nil; isBusy = false
        coordinator.dismiss(id: activityID)
        state = .init(); pendingSeek = nil
    }
    public func use(_ provider: any MediaProviding) {
        stop(); self.provider = provider; errorMessage = nil; start()
    }
    /// Provider snapshots are the only input; activity identity stays stable across progress/track changes.
    public func receive(_ value: MediaState) {
        if let pendingSeek, pendingSeek.accepts(value) { self.pendingSeek = nil }
        state = value
        errorMessage = value.issue
        if value.hasMedia {
            coordinator.present(.init(id: activityID, kind: .media, title: "Media",
                                      subtitle: nil, priority: 20, duration: nil))
        } else { coordinator.dismiss(id: activityID) }
    }
    public func displayedPosition(at now: Date) -> Double {
        pendingSeek?.position ?? estimatedPlaybackPosition(at: now, state: state)
    }
    public func seek(to position: Double, at now: Date = Date()) {
        guard !isBusy, state.canSeek, position.isFinite else { return }
        pendingSeek = PendingMediaSeek(position: min(max(position, 0), state.validDuration ?? 0),
                                       requestedAt: now, origin: state)
        send(.seek(pendingSeek!.position))
    }
    public func send(_ command: MediaCommand) {
        guard !isBusy, state.hasMedia, state.capabilities.supports(command) else { return }
        isBusy = true
        let provider = provider
        let generation = generation
        commandTask = Task { [weak self] in
            do {
                if case .seek(let position) = command { try await provider.seek(to: position) }
                else { try await provider.perform(command) }
                guard let self, self.generation == generation else { return }
                self.errorMessage = nil; self.isBusy = false
            } catch {
                guard let self, self.generation == generation else { return }
                if case .seek = command { self.pendingSeek = nil }
                self.errorMessage = (error as? MediaFailure)?.errorDescription ?? "Playback command failed."
                self.isBusy = false
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
