import Foundation
import NotchiumCore

public struct CaffeineSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let isActive: Bool
    public let expiresAt: Date?

    public init(
        availability: FeatureAvailability,
        isActive: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.availability = availability
        self.isActive = isActive
        self.expiresAt = expiresAt
    }
}

public protocol CaffeineService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<CaffeineSnapshot>
    func activate(for duration: Duration?) async throws
    func deactivate() async
}

public struct RealCaffeineService: CaffeineService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.caffeine)
    }

    public func updates() async -> AsyncStream<CaffeineSnapshot> {
        oneShotStream(CaffeineSnapshot(availability: stageOneUnavailable(.caffeine)))
    }

    public func activate(for duration: Duration?) async throws {
        throw ServiceFailure.stageTwoRequired(.caffeine)
    }

    public func deactivate() async {}
}

public struct MockCaffeineService: CaffeineService {
    public let snapshot: CaffeineSnapshot

    public init(snapshot: CaffeineSnapshot = CaffeineSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<CaffeineSnapshot> {
        oneShotStream(snapshot)
    }

    public func activate(for duration: Duration?) async throws {}
    public func deactivate() async {}
}
