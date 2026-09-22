import Foundation
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
