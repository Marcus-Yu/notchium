import Foundation
import NotchCore

public struct ShelfItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let storedURL: URL

    public init(id: UUID, displayName: String, storedURL: URL) {
        self.id = id
        self.displayName = displayName
        self.storedURL = storedURL
    }
}

public struct ShelfSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let items: [ShelfItem]

    public init(availability: FeatureAvailability, items: [ShelfItem] = []) {
        self.availability = availability
        self.items = items
    }
}

public protocol ShelfService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<ShelfSnapshot>
    func importCopies(from urls: [URL]) async throws
    func remove(ids: Set<UUID>) async throws
}

public struct RealShelfService: ShelfService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.shelf)
    }

    public func updates() async -> AsyncStream<ShelfSnapshot> {
        oneShotStream(ShelfSnapshot(availability: stageOneUnavailable(.shelf)))
    }

    public func importCopies(from urls: [URL]) async throws {
        throw ServiceFailure.stageTwoRequired(.shelf)
    }

    public func remove(ids: Set<UUID>) async throws {
        throw ServiceFailure.stageTwoRequired(.shelf)
    }
}

public struct MockShelfService: ShelfService {
    public let snapshot: ShelfSnapshot

    public init(snapshot: ShelfSnapshot = ShelfSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<ShelfSnapshot> {
        oneShotStream(snapshot)
    }

    public func importCopies(from urls: [URL]) async throws {}
    public func remove(ids: Set<UUID>) async throws {}
}
