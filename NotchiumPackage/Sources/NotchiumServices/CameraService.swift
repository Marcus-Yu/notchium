import NotchiumCore

public enum CameraState: String, Sendable {
    case inactive
    case previewing
    case unavailable
}

public struct CameraSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let state: CameraState

    public init(
        availability: FeatureAvailability,
        state: CameraState = .inactive
    ) {
        self.availability = availability
        self.state = state
    }
}

public protocol CameraService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<CameraSnapshot>
    func startPreview() async throws
    func stopPreview() async
}

public struct RealCameraService: CameraService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.camera)
    }

    public func updates() async -> AsyncStream<CameraSnapshot> {
        oneShotStream(CameraSnapshot(availability: stageOneUnavailable(.camera)))
    }

    public func startPreview() async throws {
        throw ServiceFailure.stageTwoRequired(.camera)
    }

    public func stopPreview() async {}
}

public struct MockCameraService: CameraService {
    public let snapshot: CameraSnapshot

    public init(snapshot: CameraSnapshot = CameraSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<CameraSnapshot> {
        oneShotStream(snapshot)
    }

    public func startPreview() async throws {}
    public func stopPreview() async {}
}
