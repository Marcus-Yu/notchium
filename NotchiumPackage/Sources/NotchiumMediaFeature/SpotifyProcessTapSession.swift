import Foundation
import CoreGraphics

protocol SpotifyProcessTapping: AnyObject, Sendable {
    func start(processIdentifier: pid_t) throws
    func stop()
}

/// HAL calls may wait for audio hardware or permission. One non-UI executor owns
/// every tap mutation, including cleanup; newer stop/reconnect requests supersede old ones.
actor SpotifyProcessTapSession {
    typealias Levels = @Sendable ([CGFloat]) -> Void
    private let makeTap: @Sendable (@escaping Levels) -> any SpotifyProcessTapping
    private var tap: (any SpotifyProcessTapping)?
    private var generation: UInt64 = 0

    init(makeTap: @escaping @Sendable (@escaping Levels) -> any SpotifyProcessTapping = {
        CoreAudioProcessTap(publish: $0)
    }) { self.makeTap = makeTap }

    func replace(processIdentifier: pid_t, generation: UInt64, levels: @escaping Levels) throws {
        guard generation >= self.generation, !Task.isCancelled else { return }
        self.generation = generation
        tap?.stop()
        tap = nil
        let candidate = makeTap(levels)
        do {
            try candidate.start(processIdentifier: processIdentifier)
            tap = candidate
        } catch {
            candidate.stop()
            throw error
        }
    }

    func stop(generation: UInt64) {
        guard generation >= self.generation else { return }
        self.generation = generation
        tap?.stop()
        tap = nil
    }

    isolated deinit { tap?.stop() }
}
