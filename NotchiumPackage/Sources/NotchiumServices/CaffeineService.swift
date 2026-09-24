import Foundation
import IOKit.pwr_mgt
import NotchiumCore
import Synchronization

public struct CaffeineSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let mode: CaffeineMode
    public var isActive: Bool { mode.isActive }

    public init(
        availability: FeatureAvailability,
        mode: CaffeineMode = .off
    ) {
        self.availability = availability
        self.mode = mode
    }
}

public enum CaffeineFailure: Error, Equatable, Sendable {
    case assertionCreationFailed(Int32)
}

public protocol CaffeineService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<CaffeineSnapshot>
    func setMode(_ mode: CaffeineMode) async throws
    func shutdown()
}

public final class RealCaffeineService: CaffeineService {
    private struct State {
        var mode: CaffeineMode = .off
        var assertionID: IOPMAssertionID?
        var continuations: [UUID: AsyncStream<CaffeineSnapshot>.Continuation] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    deinit { shutdown() }

    public func availability() async -> FeatureAvailability { .available }

    public func updates() async -> AsyncStream<CaffeineSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            let snapshot = state.withLock { state -> CaffeineSnapshot in
                state.continuations[id] = continuation
                return CaffeineSnapshot(availability: .available, mode: state.mode)
            }
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.continuations[id] = nil }
            }
        }
    }

    public func setMode(_ mode: CaffeineMode) async throws {
        if mode == .off {
            shutdown()
            return
        }

        var assertionID = IOPMAssertionID()
        let assertionType = mode == .system
            ? kIOPMAssertionTypePreventUserIdleSystemSleep
            : kIOPMAssertionTypePreventUserIdleDisplaySleep
        let result = IOPMAssertionCreateWithName(
            assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Notchium Caffeine" as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            throw CaffeineFailure.assertionCreationFailed(result)
        }

        let emission = state.withLock { state -> (IOPMAssertionID?, CaffeineSnapshot, [AsyncStream<CaffeineSnapshot>.Continuation]) in
            let old = state.assertionID
            state.assertionID = assertionID
            state.mode = mode
            return (old, Self.snapshot(from: state), Array(state.continuations.values))
        }
        for continuation in emission.2 { continuation.yield(emission.1) }
        if let previous = emission.0 { IOPMAssertionRelease(previous) }
    }

    public func shutdown() {
        let emission = state.withLock { state -> (IOPMAssertionID?, CaffeineSnapshot?, [AsyncStream<CaffeineSnapshot>.Continuation]) in
            let assertion = state.assertionID
            let changed = assertion != nil || state.mode != .off
            state.assertionID = nil
            state.mode = .off
            return (
                assertion,
                changed ? Self.snapshot(from: state) : nil,
                changed ? Array(state.continuations.values) : []
            )
        }
        if let snapshot = emission.1 {
            for continuation in emission.2 { continuation.yield(snapshot) }
        }
        if let assertion = emission.0 { IOPMAssertionRelease(assertion) }
    }

    private static func snapshot(from state: borrowing State) -> CaffeineSnapshot {
        CaffeineSnapshot(availability: .available, mode: state.mode)
    }
}

public final class MockCaffeineService: CaffeineService {
    private struct State {
        var snapshot: CaffeineSnapshot
        var continuations: [UUID: AsyncStream<CaffeineSnapshot>.Continuation] = [:]
    }

    private let state: Mutex<State>

    public init(snapshot: CaffeineSnapshot = CaffeineSnapshot(availability: .available)) {
        state = Mutex(State(snapshot: snapshot))
    }

    public func availability() async -> FeatureAvailability {
        state.withLock { $0.snapshot.availability }
    }

    public func updates() async -> AsyncStream<CaffeineSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            let snapshot = state.withLock { state -> CaffeineSnapshot in
                state.continuations[id] = continuation
                return state.snapshot
            }
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.continuations[id] = nil }
            }
        }
    }

    public func setMode(_ mode: CaffeineMode) async throws {
        let emission = state.withLock { state in
            state.snapshot = CaffeineSnapshot(availability: state.snapshot.availability, mode: mode)
            return (state.snapshot, Array(state.continuations.values))
        }
        for continuation in emission.1 { continuation.yield(emission.0) }
    }

    public func shutdown() {
        let emission = state.withLock { state in
            state.snapshot = CaffeineSnapshot(availability: state.snapshot.availability, mode: .off)
            return (state.snapshot, Array(state.continuations.values))
        }
        for continuation in emission.1 { continuation.yield(emission.0) }
    }
}
