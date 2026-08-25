import Foundation
import NotchCore

public struct CalendarEventSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let meetingURL: URL?

    public init(
        id: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        meetingURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.meetingURL = meetingURL
    }
}

public struct CalendarSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let upcomingEvents: [CalendarEventSummary]

    public init(
        availability: FeatureAvailability,
        upcomingEvents: [CalendarEventSummary] = []
    ) {
        self.availability = availability
        self.upcomingEvents = upcomingEvents
    }
}

public protocol CalendarService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<CalendarSnapshot>
    func refresh() async throws
}

public struct RealCalendarService: CalendarService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.calendar)
    }

    public func updates() async -> AsyncStream<CalendarSnapshot> {
        oneShotStream(CalendarSnapshot(availability: stageOneUnavailable(.calendar)))
    }

    public func refresh() async throws {
        throw ServiceFailure.stageTwoRequired(.calendar)
    }
}

public struct MockCalendarService: CalendarService {
    public let snapshot: CalendarSnapshot

    public init(snapshot: CalendarSnapshot = CalendarSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<CalendarSnapshot> {
        oneShotStream(snapshot)
    }

    public func refresh() async throws {}
}
