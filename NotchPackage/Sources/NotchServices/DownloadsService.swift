import Foundation
import NotchCore

public enum DownloadState: String, Sendable {
    case stabilizing
    case complete
}

public struct DownloadItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let fileURL: URL
    public let state: DownloadState

    public init(id: UUID, displayName: String, fileURL: URL, state: DownloadState) {
        self.id = id
        self.displayName = displayName
        self.fileURL = fileURL
        self.state = state
    }
}

public struct DownloadsSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let items: [DownloadItem]

    public init(availability: FeatureAvailability, items: [DownloadItem] = []) {
        self.availability = availability
        self.items = items
    }
}

public protocol DownloadsService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<DownloadsSnapshot>
    func refresh() async throws
}

public struct RealDownloadsService: DownloadsService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.downloads)
    }

    public func updates() async -> AsyncStream<DownloadsSnapshot> {
        oneShotStream(DownloadsSnapshot(availability: stageOneUnavailable(.downloads)))
    }

    public func refresh() async throws {
        throw ServiceFailure.stageTwoRequired(.downloads)
    }
}

public struct MockDownloadsService: DownloadsService {
    public let snapshot: DownloadsSnapshot

    public init(snapshot: DownloadsSnapshot = DownloadsSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<DownloadsSnapshot> {
        oneShotStream(snapshot)
    }

    public func refresh() async throws {}
}
