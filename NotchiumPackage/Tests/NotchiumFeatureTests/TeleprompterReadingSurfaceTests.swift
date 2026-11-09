import Foundation
import NotchiumCore
@testable import NotchiumDynamicIsland
import NotchiumPersistence
import NotchiumServices
@testable import NotchiumTeleprompterFeature
import XCTest

/// The native reading surface must survive ordinary meeting interaction while capture
/// remains active, including the first-use system microphone permission dialog.
@MainActor
final class TeleprompterReadingSurfaceTests: XCTestCase {
    func testReadingStartPromotesHoverAndCancelsPendingHoverBeforeCapture() async {
        let fixture = fixture(events: [.preparing])
        defer { fixture.stop() }
        fixture.presentation.setHovered(true)
        await drainTasks()
        XCTAssertEqual(fixture.presentation.visualState, .hovered)

        fixture.presentation.prepareForTeleprompterReading()
        XCTAssertEqual(fixture.presentation.visualState, .expanded)
        XCTAssertEqual(fixture.presentation.pageModel.selectedPage, .teleprompter)
        fixture.model.session.start()
        XCTAssertEqual(fixture.model.session.state, .preparing)

        // A delayed hover-entry callback must not demote an explicitly started reader.
        await drainTasks()
        await fixture.clock.advance(by: .seconds(2))
        await drainTasks()
        XCTAssertEqual(fixture.presentation.visualState, .expanded)
        XCTAssertTrue(fixture.model.session.isActive)

        fixture.presentation.setHovered(false)
        await drainTasks()
        await fixture.clock.advance(by: .seconds(2))
        await drainTasks()
        XCTAssertEqual(fixture.presentation.visualState, .expanded)
        XCTAssertTrue(fixture.model.session.isActive)
    }

    func testPermissionPreparationAndModelDownloadHoldOutsideClicks() async {
        let cases: [([TeleprompterSpeechEvent], TeleprompterReadingState)] = [
            ([TeleprompterSpeechEvent.preparing], TeleprompterReadingState.preparing),
            ([.downloadingAssets], .downloading)
        ]
        for (events, state) in cases {
            let fixture = fixture(events: events)
            fixture.presentation.prepareForTeleprompterReading()
            fixture.model.session.start()
            await eventually { fixture.model.session.state == state }
            XCTAssertFalse(fixture.presentation.collapsesOnOutsideClick,
                           "Clicking Allow or interacting with model setup must not cancel capture preparation")
            fixture.stop()
        }
    }

    func testWaitingAndFollowingHoldOutsideClicks() async {
        let cases: [([TeleprompterSpeechEvent], TeleprompterReadingState)] = [
            ([TeleprompterSpeechEvent.ready], TeleprompterReadingState.waiting),
            ([.ready, .transcript(text: "Welcome everyone to our", audioStart: 0, audioEnd: 1, isFinal: false)], .reading)
        ]
        for (events, state) in cases {
            let fixture = fixture(events: events)
            fixture.presentation.prepareForTeleprompterReading()
            fixture.model.session.start()
            await eventually { fixture.model.session.state == state }
            XCTAssertFalse(fixture.presentation.collapsesOnOutsideClick,
                           "Clicking controls in the meeting app must keep the active reader visible")
            fixture.stop()
        }
    }

    func testPauseRestoresOrdinaryOutsideClickDismissal() async {
        let fixture = fixture(events: [.ready])
        defer { fixture.stop() }
        fixture.presentation.prepareForTeleprompterReading()
        fixture.model.session.start()
        await eventually { fixture.model.session.state == .waiting }
        XCTAssertFalse(fixture.presentation.collapsesOnOutsideClick)

        fixture.model.session.pause()
        XCTAssertEqual(fixture.model.session.state, .paused)
        XCTAssertTrue(fixture.presentation.collapsesOnOutsideClick)
    }

    func testPageChangeRestoresDismissalAndVisibilityTeardownPausesCapture() async {
        let fixture = fixture(events: [.ready])
        defer { fixture.stop() }
        fixture.presentation.prepareForTeleprompterReading()
        fixture.model.session.start()
        await eventually { fixture.model.session.state == .waiting }

        fixture.presentation.pageModel.selectedPage = .calendar
        XCTAssertTrue(fixture.presentation.collapsesOnOutsideClick)
        // This is the renderer visibility callback delivered by NotchPagesView.
        fixture.model.setReadingVisible(false, source: fixture.source)
        XCTAssertEqual(fixture.model.session.state, .paused)
    }

    func testExplicitEscapeCanCloseTheActiveReaderAndReleaseCapture() async {
        let fixture = fixture(events: [.ready])
        defer { fixture.stop() }
        fixture.presentation.prepareForTeleprompterReading()
        fixture.model.session.start()
        await eventually { fixture.model.session.state == .waiting }
        XCTAssertFalse(fixture.presentation.collapsesOnOutsideClick)

        fixture.presentation.handleEscape()
        XCTAssertEqual(fixture.presentation.visualState, .collapsed)
        fixture.model.setReadingVisible(false, source: fixture.source)
        XCTAssertEqual(fixture.model.session.state, .paused)
    }

    func testFeatureDisabledPageCannotBeOpenedByReadingPreparation() {
        let fixture = fixture(events: [.preparing])
        defer { fixture.stop() }
        fixture.presentation.pageModel.enabledPages = [.home, .calendar]
        fixture.presentation.pageModel.selectedPage = .calendar
        fixture.presentation.prepareForTeleprompterReading()
        XCTAssertEqual(fixture.presentation.visualState, .hovered)
        XCTAssertEqual(fixture.presentation.pageModel.selectedPage, .calendar)
    }

    @MainActor private struct Fixture {
        let presentation: DynamicIslandPresentationModel
        let model: TeleprompterModel
        let clock: TestAppClock
        let source: String

        func stop() {
            model.stop()
            presentation.reset()
        }
    }

    private func fixture(events: [TeleprompterSpeechEvent]) -> Fixture {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 1_800_000_000), automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        let model = TeleprompterModel(speech: MockTeleprompterSpeechService(events: events),
            store: MockTeleprompterScriptStore(), importer: MockTeleprompterDocumentService(),
            meetingContext: MockTeleprompterMeetingContextService(), calendar: MockCalendarService(),
            activities: presentation.activityCoordinator, clock: clock,
            uuids: SequenceUUIDGenerator(values: []))
        presentation.teleprompterRenderer = model
        let source = presentation.cameraPresentationSource
        model.setReadingVisible(true, source: source)
        model.session.prepare(text: "Welcome everyone to our quarterly report. Customer retention increased across every region.")
        return Fixture(presentation: presentation, model: model, clock: clock, source: source)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected reading-surface state did not arrive")
    }

    private func drainTasks() async {
        for _ in 0..<50 { await Task.yield() }
    }
}
