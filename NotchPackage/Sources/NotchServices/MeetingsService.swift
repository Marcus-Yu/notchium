import Foundation
import NotchCore

public enum MeetingProvider: String, Sendable {
    case zoom
    case googleMeet
    case microsoftTeams
    case web
}

public struct MeetingSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let provider: MeetingProvider
    public let joinURL: URL
    public let startsAt: Date

    public init(id: UUID, provider: MeetingProvider, joinURL: URL, startsAt: Date) {
        self.id = id
        self.provider = provider
        self.joinURL = joinURL
        self.startsAt = startsAt
    }
}

public struct MeetingsSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let upcoming: [MeetingSummary]

    public init(availability: FeatureAvailability, upcoming: [MeetingSummary] = []) {
        self.availability = availability
        self.upcoming = upcoming
    }
}

public protocol MeetingsService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<MeetingsSnapshot>
    func join(_ meeting: MeetingSummary) async throws
}

public struct RealMeetingsService: MeetingsService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.meetings)
    }

    public func updates() async -> AsyncStream<MeetingsSnapshot> {
        oneShotStream(MeetingsSnapshot(availability: stageOneUnavailable(.meetings)))
    }

    public func join(_ meeting: MeetingSummary) async throws {
        throw ServiceFailure.stageTwoRequired(.meetings)
    }
}

public struct MockMeetingsService: MeetingsService {
    public let snapshot: MeetingsSnapshot

    public init(snapshot: MeetingsSnapshot = MeetingsSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<MeetingsSnapshot> {
        oneShotStream(snapshot)
    }

    public func join(_ meeting: MeetingSummary) async throws {}
}
