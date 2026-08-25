import Foundation
import NotchiumCore

public struct ScreenshotItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let createdAt: Date

    public init(id: UUID, fileURL: URL, createdAt: Date) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
    }
}

public struct ScreenshotSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let recent: [ScreenshotItem]

    public init(availability: FeatureAvailability, recent: [ScreenshotItem] = []) {
        self.availability = availability
        self.recent = recent
    }
}

public protocol ScreenshotService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<ScreenshotSnapshot>
    func refresh() async throws
}

public struct RealScreenshotService: ScreenshotService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.screenshot)
    }

    public func updates() async -> AsyncStream<ScreenshotSnapshot> {
        oneShotStream(ScreenshotSnapshot(availability: stageOneUnavailable(.screenshot)))
    }

    public func refresh() async throws {
        throw ServiceFailure.stageTwoRequired(.screenshot)
    }
}

public struct MockScreenshotService: ScreenshotService {
    public let snapshot: ScreenshotSnapshot

    public init(snapshot: ScreenshotSnapshot = ScreenshotSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<ScreenshotSnapshot> {
        oneShotStream(snapshot)
    }

    public func refresh() async throws {}
}
