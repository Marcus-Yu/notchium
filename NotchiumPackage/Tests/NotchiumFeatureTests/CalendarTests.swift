import Foundation
import NotchiumCore
import NotchiumCalendarFeature
@testable import NotchiumDynamicIsland
import NotchiumServices
import XCTest

final class CalendarTests: XCTestCase {
    func testEventLifecycleAtApproachStartAndEnd() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(1_800)
        XCTAssertEqual(CalendarEventStatus.status(start: start, end: end,
            at: start.addingTimeInterval(-901)), .upcoming)
        XCTAssertEqual(CalendarEventStatus.status(start: start, end: end,
            at: start.addingTimeInterval(-900)), .startingSoon)
        XCTAssertEqual(CalendarEventStatus.status(start: start, end: end, at: start), .now)
        XCTAssertEqual(CalendarEventStatus.status(start: start, end: end,
            at: start.addingTimeInterval(60)), .inProgress)
        XCTAssertEqual(CalendarEventStatus.status(start: start, end: end, at: end), .ended)
    }

    func testMeetingLinksFromEventURLLocationAndNotes() {
        XCTAssertEqual(MeetingLinkDetector.detect(
            url: URL(string: "https://us02web.zoom.us/j/123456789"),
            location: nil, notes: nil)?.host, "us02web.zoom.us")
        XCTAssertEqual(MeetingLinkDetector.detect(url: nil,
            location: "Join at https://meet.google.com/abc-defg-hij.", notes: nil)?.absoluteString,
            "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(MeetingLinkDetector.detect(url: nil, location: nil,
            notes: "Teams: https://teams.microsoft.com/l/meetup-join/abc")?.host,
            "teams.microsoft.com")
    }

    func testMeetingLinksRejectSpoofedAndUnsafeURLs() {
        XCTAssertNil(MeetingLinkDetector.detect(url: URL(string: "http://zoom.us/j/123"),
            location: nil, notes: nil))
        XCTAssertNil(MeetingLinkDetector.detect(url: nil,
            location: "https://zoom.us.evil.example/j/123", notes: nil))
        XCTAssertNil(MeetingLinkDetector.detect(url: URL(string: "https://user@meet.google.com/abc"),
            location: nil, notes: nil))
        XCTAssertNil(MeetingLinkDetector.detect(url: nil, location: nil,
            notes: "No meeting link here"))
        XCTAssertNil(MeetingLinkDetector.detect(url: URL(string: "https://zoom.us/signin"),
            location: nil, notes: nil))
        XCTAssertNil(MeetingLinkDetector.detect(url: URL(string: "https://meet.google.com"),
            location: nil, notes: nil))
    }
}

/// Mirrors RealCalendarService: one observation session, and stop finishes every stream.
@MainActor
private final class SessionCalendarService: CalendarService {
    private var continuations: [AsyncStream<CalendarSnapshot>.Continuation] = []
    private var started = false
    private(set) var sessions = 0
    func availability() async -> FeatureAvailability { .available }
    func updates() async -> AsyncStream<CalendarSnapshot> {
        if !started { started = true; sessions += 1 }
        let pair = AsyncStream<CalendarSnapshot>.makeStream()
        continuations.append(pair.continuation)
        return pair.stream
    }
    func emit(_ snapshot: CalendarSnapshot) { continuations.forEach { $0.yield(snapshot) } }
    func refresh() async throws {}
    func requestAccess() async {}
    func setCalendarSelected(_ id: String, selected: Bool) async {}
    func stop() async {
        continuations.forEach { $0.finish() }
        continuations.removeAll()
        started = false
    }
}

@MainActor
final class CalendarRestartTests: XCTestCase {
    func testImmediateRestartSubscribesAfterPreviousStopFinishes() async {
        let service = SessionCalendarService()
        let model = CalendarActivityModel(service: service, coordinator: ActivityCoordinator(
            clock: TestAppClock(now: Date(), automaticallyAdvances: false)))
        model.start()
        for _ in 0..<20 { await Task.yield() }
        model.stop()
        model.start()
        for _ in 0..<40 { await Task.yield() }
        XCTAssertEqual(service.sessions, 2)
        let event = CalendarEventSummary(id: UUID(), title: "Restarted",
            startDate: Date().addingTimeInterval(7200), endDate: Date().addingTimeInterval(9000))
        service.emit(CalendarSnapshot(availability: .available, upcomingEvents: [event]))
        for _ in 0..<40 { await Task.yield() }
        XCTAssertEqual(model.snapshot.upcomingEvents.map(\.title), ["Restarted"])
        model.stop()
    }
}
