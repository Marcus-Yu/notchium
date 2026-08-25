import Foundation
import NotchCore

public enum ClipboardItemKind: String, Sendable {
    case text
    case url
    case image
    case file
}

public struct ClipboardItemMetadata: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: ClipboardItemKind
    public let capturedAt: Date
    public let isPinned: Bool
    public let isFavorite: Bool

    public init(
        id: UUID,
        kind: ClipboardItemKind,
        capturedAt: Date,
        isPinned: Bool = false,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.capturedAt = capturedAt
        self.isPinned = isPinned
        self.isFavorite = isFavorite
    }
}

public struct ClipboardSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let items: [ClipboardItemMetadata]

    public init(
        availability: FeatureAvailability,
        items: [ClipboardItemMetadata] = []
    ) {
        self.availability = availability
        self.items = items
    }
}

public protocol ClipboardService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<ClipboardSnapshot>
    func delete(id: UUID) async throws
    func setPinned(_ isPinned: Bool, id: UUID) async throws
}

public struct RealClipboardService: ClipboardService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.clipboard)
    }

    public func updates() async -> AsyncStream<ClipboardSnapshot> {
        oneShotStream(ClipboardSnapshot(availability: stageOneUnavailable(.clipboard)))
    }

    public func delete(id: UUID) async throws {
        throw ServiceFailure.stageTwoRequired(.clipboard)
    }

    public func setPinned(_ isPinned: Bool, id: UUID) async throws {
        throw ServiceFailure.stageTwoRequired(.clipboard)
    }
}

public struct MockClipboardService: ClipboardService {
    public let snapshot: ClipboardSnapshot

    public init(snapshot: ClipboardSnapshot = ClipboardSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<ClipboardSnapshot> {
        oneShotStream(snapshot)
    }

    public func delete(id: UUID) async throws {}
    public func setPinned(_ isPinned: Bool, id: UUID) async throws {}
}
