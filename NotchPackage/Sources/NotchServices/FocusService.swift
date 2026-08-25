import Foundation
import NotchCore

public enum FocusPhase: String, Sendable {
    case idle
    case focusing
    case breakTime
    case paused
    case completed
}

public struct FocusSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let phase: FocusPhase
    public let startedAt: Date?
    public let endsAt: Date?

    public init(
        availability: FeatureAvailability,
        phase: FocusPhase = .idle,
        startedAt: Date? = nil,
        endsAt: Date? = nil
    ) {
        self.availability = availability
        self.phase = phase
        self.startedAt = startedAt
        self.endsAt = endsAt
    }
}

public protocol FocusService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<FocusSnapshot>
    func start(focusDuration: Duration, breakDuration: Duration) async throws
    func pause() async throws
    func stop() async
}

public struct RealFocusService: FocusService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.focus)
    }

    public func updates() async -> AsyncStream<FocusSnapshot> {
        oneShotStream(FocusSnapshot(availability: stageOneUnavailable(.focus)))
    }

    public func start(focusDuration: Duration, breakDuration: Duration) async throws {
        throw ServiceFailure.stageTwoRequired(.focus)
    }

    public func pause() async throws {
        throw ServiceFailure.stageTwoRequired(.focus)
    }

    public func stop() async {}
}

public struct MockFocusService: FocusService {
    public let snapshot: FocusSnapshot

    public init(snapshot: FocusSnapshot = FocusSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<FocusSnapshot> {
        oneShotStream(snapshot)
    }

    public func start(focusDuration: Duration, breakDuration: Duration) async throws {}
    public func pause() async throws {}
    public func stop() async {}
}
