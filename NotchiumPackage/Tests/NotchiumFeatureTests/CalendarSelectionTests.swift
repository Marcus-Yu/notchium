import AppKit
import SwiftUI
import XCTest
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
@testable import NotchiumCalendarFeature

@MainActor
final class CalendarSelectionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_007_200)

    private func events() -> [CalendarEventSummary] {
        [
            CalendarEventSummary(id: UUID(), title: "Class", startDate: start,
                endDate: start.addingTimeInterval(3600),
                meetingURL: MeetingLinkDetector.detect(url: URL(string: "https://zoom.us/j/123456789"),
                    location: nil, notes: nil)),
            CalendarEventSummary(id: UUID(), title: "Interview", startDate: start.addingTimeInterval(900),
                endDate: start.addingTimeInterval(2700),
                meetingURL: MeetingLinkDetector.detect(url: nil, location: nil,
                    notes: "Join https://teams.microsoft.com/l/meetup-join/interview")),
            CalendarEventSummary(id: UUID(), title: "Meeting", startDate: start.addingTimeInterval(5400),
                endDate: start.addingTimeInterval(7200), location: "Room 4")
        ]
    }

    private func model(openMeeting: @escaping @MainActor (URL) -> Void = { _ in }) -> CalendarActivityModel {
        let clock = TestAppClock(now: start.addingTimeInterval(600), automaticallyAdvances: false)
        return CalendarActivityModel(service: MockCalendarService(),
            coordinator: ActivityCoordinator(clock: clock), clock: clock, openMeeting: openMeeting)
    }

    func testOverlappingEventCanExpandAndJoinItsOwnLink() {
        let events = events()
        var opened: [URL] = []
        let model = model { opened.append($0) }
        model.receive(.init(availability: .available, upcomingEvents: events))
        let now = start.addingTimeInterval(600) // 10:10 relative to the 10:00 class.
        XCTAssertEqual(events[0].status(at: now), .inProgress)
        XCTAssertEqual(events[1].status(at: now), .startingSoon)
        XCTAssertEqual(model.snapshot.nextEvent?.id, events[0].id)

        model.toggleEvent(events[1].id)
        XCTAssertEqual(model.selectedEventID, events[1].id)
        model.joinEvent(events[1].id)
        XCTAssertEqual(opened, [events[1].meetingURL!])
        XCTAssertEqual(model.snapshot.nextEvent?.id, events[0].id)
        XCTAssertEqual(model.selectedEventID, events[1].id)

        model.toggleEvent(events[2].id)
        XCTAssertEqual(model.selectedEventID, events[2].id)
        XCTAssertNil(events[2].meetingURL)
        model.joinEvent(events[2].id)
        XCTAssertEqual(opened.count, 1)
        model.toggleEvent(events[2].id)
        XCTAssertNil(model.selectedEventID)
        model.joinEvent(events[0].id)
        XCTAssertEqual(opened.last, events[0].meetingURL)
    }

    func testSelectionSurvivesRefreshAndReorderingButClearsOnRemoval() {
        let events = events()
        let model = model()
        model.receive(.init(availability: .available, upcomingEvents: events))
        model.toggleEvent(events[1].id)
        let updated = CalendarEventSummary(id: events[1].id, title: "Updated Interview",
            startDate: events[1].startDate, endDate: events[1].endDate,
            meetingURL: events[1].meetingURL)
        model.receive(.init(availability: .available, upcomingEvents: [events[0], events[2], updated]))
        XCTAssertEqual(model.selectedEventID, updated.id)
        // Promotion to the primary slot does not replace selection with another row.
        model.receive(.init(availability: .available, upcomingEvents: [updated, events[2]]))
        XCTAssertEqual(model.selectedEventID, updated.id)
        model.receive(.init(availability: .available, upcomingEvents: [events[2]]))
        XCTAssertNil(model.selectedEventID)
        model.toggleEvent(updated.id)
        XCTAssertNil(model.selectedEventID)
    }

    func testAllSecondaryEventsRemainSelectableAndJoinResolvesLatestSnapshot() {
        var events = events()
        events += (0..<10).map { index in
            CalendarEventSummary(id: UUID(), title: "Later \(index)",
                startDate: start.addingTimeInterval(Double(index + 3) * 3600),
                endDate: start.addingTimeInterval(Double(index + 4) * 3600))
        }
        var opened: [URL] = []
        let model = model { opened.append($0) }
        model.receive(.init(availability: .available, upcomingEvents: events))
        XCTAssertEqual(model.secondaryEvents.count, 12)
        for event in events.dropFirst() {
            model.toggleEvent(event.id)
            XCTAssertEqual(model.selectedEventID, event.id)
        }
        let newURL = URL(string: "https://meet.google.com/abc-defg-hij")!
        let updated = CalendarEventSummary(id: events[1].id, title: "Interview",
            startDate: events[1].startDate, endDate: events[1].endDate, meetingURL: newURL)
        model.receive(.init(availability: .available, upcomingEvents: [events[0], updated]))
        model.joinEvent(updated.id)
        XCTAssertEqual(opened, [newURL])
        model.receive(.init(availability: .unavailable(.permissionDenied), permission: .denied))
        model.joinEvent(updated.id)
        XCTAssertEqual(opened.count, 1)
        XCTAssertNil(model.selectedEventID)
    }

    func testCalendarSelectionRendersWithinCanonicalContentSize() async throws {
        let titles = ["Introduction to Financial Mathematics", "Software Engineering Interview",
                      "Weekly Product Development Meeting", "Computer Science Tutorial"]
        let events = titles.enumerated().map { index, title in
            CalendarEventSummary(id: UUID(), title: title,
                startDate: start.addingTimeInterval(Double(index) * 1800),
                endDate: start.addingTimeInterval(Double(index + 1) * 1800),
                meetingURL: index < 2 ? URL(string: "https://teams.microsoft.com/l/meetup-join/interview") : nil,
                location: index == 2 ? "Room 4" : nil)
        }
        let model = model()
        model.receive(.init(availability: .available, upcomingEvents: events))
        let content = CalendarActivityView(model: model)
            .frame(width: ExpandedNotchLayout.size.width,
                   height: ExpandedNotchLayout.size.height - 38 - ExpandedNotchLayout.navigationHeight)
            .background(.black)
            .environment(\.colorScheme, .dark)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(x: 0, y: 0, width: 524, height: 196)
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 524, height: 196),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        for selection in [nil, events[1].id, events[2].id] {
            if let selection { model.toggleEvent(selection) }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            host.needsDisplay = true
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertEqual(bitmap.size.width, 524)
            XCTAssertEqual(bitmap.size.height, 196)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let name = selection == events[1].id ? "interview" : selection == events[2].id ? "meeting" : "collapsed"
            try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-calendar-selection-\(name).png"))
        }
    }
}
