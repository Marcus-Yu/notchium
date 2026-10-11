import Foundation
import Synchronization

/// A small reservation ledger shared by the event callback and serial worker.
final class VolumeInputGate: Sendable {
    struct Route: Equatable, Sendable {
        let deviceID: UInt32
        let volume: Bool
        let mute: Bool
    }
    private struct State {
        var route: Route?
        var generation: UInt64 = 0
        var pending = 0
        var live = true
    }
    private let state = Mutex(State())
    static let maximumPending = 32
    var isLive: Bool { state.withLock { $0.live } }
    func close() { state.withLock { $0.generation &+= 1; $0.route = nil; $0.live = false } }

    func configure(_ route: Route?) {
        state.withLock {
            guard $0.live, $0.route != route else { return }
            $0.generation &+= 1
            $0.route = route
        }
    }
    func supports(_ key: VolumeHardwareKey) -> Bool {
        state.withLock {
            guard $0.live, let route = $0.route else { return false }
            return key == .mute ? route.mute : route.volume
        }
    }
    func reserve(_ key: VolumeHardwareKey) -> (Route, UInt64)? {
        state.withLock {
            guard $0.live, let route = $0.route, key == .mute ? route.mute : route.volume,
                  $0.pending < Self.maximumPending else { return nil }
            $0.pending += 1
            return (route, $0.generation)
        }
    }
    func isCurrent(_ generation: UInt64) -> Bool { state.withLock { $0.generation == generation && $0.route != nil } }
    func complete() { state.withLock { $0.pending -= 1 } }
    func invalidate() { state.withLock { $0.generation &+= 1; $0.route = nil } }
}
