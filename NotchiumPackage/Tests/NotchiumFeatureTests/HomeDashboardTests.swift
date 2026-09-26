import AppKit
import SwiftUI
import XCTest
import NotchiumCore
import NotchiumServices
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature
@testable import NotchiumCalendarFeature
@testable import NotchiumFeature

@MainActor final class HomeDashboardTests: XCTestCase {
    func testHomeKeepsSelectionDuringPlaybackAndTransientActivityUntilCollapse() async {
        for state in [NotchStableState.hovered, .expanded] {
            let model = DynamicIslandPresentationModel(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
            model.present(state, animated: false)
            model.pageModel.selectedPage = .home
            model.activityCoordinator.present(.init(id: UUID(), kind: .media, title: "Track", subtitle: nil, presentationStyle: .mediaSides,
                lifetime: .persistent, destination: .music, duration: nil))
            XCTAssertEqual(model.pageModel.selectedPage, .home)
            model.activityCoordinator.present(.init(id: UUID(), kind: .calendar, title: "Event", subtitle: nil, destination: .calendar, duration: .seconds(10)))
            XCTAssertEqual(model.pageModel.selectedPage, .home)
            model.present(.collapsed, animated: false)
            model.setExpanded(true)
            XCTAssertEqual(model.pageModel.selectedPage, .home)
            model.reset()
        }
    }

    func testPausedMediaUsesExistingCommandsAndRetainsCachedTrack() async throws {
        let presentation = DynamicIslandPresentationModel(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
        let snapshot = MediaState(connectionState: .authenticated, playbackState: .paused,
            title: "Midnight City", artist: "M83", elapsed: 0, duration: 244,
            trackID: "midnight", source: .spotify,
            capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true, canSeek: true))
        let provider = MockMediaProvider(snapshot: snapshot)
        let media = MediaSessionController(provider: provider, coordinator: presentation.activityCoordinator)
        media.receive(snapshot)
        presentation.present(.expanded, animated: false)
        presentation.pageModel.selectedPage = .home
        XCTAssertTrue(media.homeMediaConnected)
        media.receive(.init(connectionState: .authenticated, source: .spotify))
        XCTAssertTrue(media.isShowingCachedTrack)
        XCTAssertEqual(media.state.title, "Midnight City")
        XCTAssertFalse(media.state.isPlaying)
        media.send(.playPause)
        await settle(media)
        XCTAssertTrue(media.state.isPlaying)
        XCTAssertEqual(presentation.pageModel.selectedPage, .home)
        media.send(.next)
        await settle(media)
        media.send(.previous)
        await settle(media)
        media.send(.playPause)
        await settle(media)
        let commands = await provider.commands
        XCTAssertEqual(commands, [.play, .next, .previous, .pause])
        XCTAssertEqual(presentation.pageModel.selectedPage, .home)
        media.receive(.init(connectionState: .unauthenticated, source: .spotify, timestamp: Date().addingTimeInterval(1)))
        XCTAssertFalse(media.homeMediaConnected, "Cached metadata must not pretend Spotify is connected")
        media.stop(); presentation.reset()
    }

    func testCalendarSummarySelectsRelevantEventAndTodayState() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 12)))
        let expired = CalendarEventSummary(id: UUID(), title: "Ended", startDate: now.addingTimeInterval(-3600), endDate: now)
        let today = CalendarEventSummary(id: UUID(), title: "Today", startDate: now.addingTimeInterval(60), endDate: now.addingTimeInterval(3600))
        let tomorrow = CalendarEventSummary(id: UUID(), title: "Tomorrow", startDate: now.addingTimeInterval(86400), endDate: now.addingTimeInterval(90000))
        let summary = HomeCalendarSummary(events: [tomorrow, expired, today], at: now, calendar: calendar)
        XCTAssertEqual(summary.nextEvent?.id, today.id)
        XCTAssertTrue(summary.hasEventsToday)
        let nextDay = HomeCalendarSummary(events: [expired, tomorrow], at: now, calendar: calendar)
        XCTAssertEqual(nextDay.nextEvent?.id, tomorrow.id)
        XCTAssertFalse(nextDay.hasEventsToday)
        let empty = HomeCalendarSummary(events: [expired], at: now, calendar: calendar)
        XCTAssertNil(empty.nextEvent)
        XCTAssertFalse(empty.hasEventsToday)
        let ongoing = CalendarEventSummary(id: UUID(), title: "All day", startDate: now.addingTimeInterval(-86400), endDate: now.addingTimeInterval(3600), isAllDay: true)
        XCTAssertTrue(HomeCalendarSummary(events: [ongoing], at: now, calendar: calendar).hasEventsToday)
    }

    func testRenderFixedHomeWithPopulatedLongAndEmptyStates() throws {
        for fixture in ["paused", "long", "empty", "disconnected", "tomorrow"] {
            let presentation = DynamicIslandPresentationModel(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
            let media = MediaSessionController(provider: MockMediaProvider(), coordinator: presentation.activityCoordinator)
            let hasTrack = fixture != "empty" && fixture != "disconnected"
            media.receive(.init(connectionState: fixture == "disconnected" ? .unauthenticated : .authenticated,
                playbackState: hasTrack ? .paused : .stopped,
                title: hasTrack ? (fixture == "long" ? String(repeating: "A very long song title ", count: 6) : "Midnight City") : nil,
                artist: hasTrack ? "M83" : nil, elapsed: 81, duration: hasTrack ? 244 : nil,
                trackID: hasTrack ? "midnight" : nil, artwork: hasTrack ? URL(string: "notchium-fixture://artwork/midnight") : nil,
                source: .spotify, capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true)))
            let calendar = CalendarActivityModel(service: MockCalendarService(), coordinator: presentation.activityCoordinator)
            let start = Date().addingTimeInterval(fixture == "tomorrow" ? 86400 : 3600)
            calendar.receive(.init(availability: .available, upcomingEvents: hasTrack ? [
                .init(id: UUID(), title: fixture == "long" ? String(repeating: "Long planning meeting ", count: 6) : "Design review", startDate: start, endDate: start.addingTimeInterval(3600))
            ] : [], permission: fixture == "disconnected" ? .denied : .granted))
            // Exclude native glass navigation, which ImageRenderer cannot capture.
            let view = HomeDashboardView(pages: presentation.pageModel, media: media, calendar: calendar)
                .frame(width: 524, height: 196).foregroundStyle(.white).background(.black).environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(x: 0, y: 0, width: 524, height: 196)
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(containsScrollView(host), "Home must not create a native scroll view")
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/private/tmp/notchium-home-simple-\(fixture).png"))
            XCTAssertEqual(bitmap.pixelsWide, 1048)
            XCTAssertEqual(bitmap.pixelsHigh, 392)
            media.stop(); calendar.stop(); presentation.reset()
        }
    }

    private func containsScrollView(_ view: NSView) -> Bool {
        view is NSScrollView || view.subviews.contains { containsScrollView($0) }
    }

    private func settle(_ media: MediaSessionController) async {
        for _ in 0..<1000 {
            if !media.isBusy { return }
            await Task.yield()
        }
        XCTFail("Media command did not finish")
    }
}

