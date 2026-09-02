import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
final class DynamicIslandPresentationTests: XCTestCase {
    func testHoverEntryIsDelayedAndCompletesDeterministically() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(clock: clock)

        model.setHovered(true)
        XCTAssertEqual(model.phase, .collapsed)

        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .transitioning(from: .collapsed, to: .hovered))

        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .hovered)
    }

    func testHoverAndCollapseUseExactForgivenessDelays() async {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0))
        let model = DynamicIslandPresentationModel(clock: clock)

        model.setHovered(true)
        await drainMainActorTasks()
        model.setHovered(false)
        await drainMainActorTasks()

        let history = await clock.sleepHistory()
        XCTAssertTrue(history.contains(.milliseconds(120)))
        XCTAssertTrue(history.contains(.milliseconds(240)))
    }

    func testCancelledHoverEntryNeverWins() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(clock: clock)

        model.setHovered(true)
        await waitForPendingSleep(clock)
        model.setHovered(false)
        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await drainMainActorTasks()

        XCTAssertEqual(model.phase, .collapsed)
    }

    func testExpandedStateCollapsesAfterHoverExitDelay() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(
            phase: .expanded,
            clock: clock
        )

        model.setHovered(false)
        XCTAssertEqual(model.phase, .expanded)

        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await drainMainActorTasks()

        XCTAssertEqual(model.phase, .transitioning(from: .expanded, to: .collapsed))
    }

    func testToggleAndOutsideDismissalUseExplicitTransitions() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(clock: clock)

        model.toggleExpanded()
        XCTAssertEqual(model.phase, .transitioning(from: .collapsed, to: .expanded))
        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .expanded)

        model.collapse()
        XCTAssertEqual(model.phase, .transitioning(from: .expanded, to: .collapsed))
        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .collapsed)
    }

    func testClickExpansionIsImmediateAndDoesNotUseTheHoverDelay() async {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0))
        let model = DynamicIslandPresentationModel(clock: clock)

        model.toggleExpanded()
        await drainMainActorTasks()

        XCTAssertEqual(model.phase, .expanded)
        let history = await clock.sleepHistory()
        XCTAssertEqual(history, [.milliseconds(780)])
    }

    func testHoverReentryCancelsPendingCollapse() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .expanded, clock: clock)

        model.setHovered(false)
        await waitForPendingSleep(clock)
        model.setHovered(true)
        await clock.releaseAll()
        await drainMainActorTasks()

        XCTAssertEqual(model.phase, .expanded)
    }

    func testStaleTransitionCompletionIsRejected() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(clock: clock)

        model.toggleExpanded()
        await waitForPendingSleep(clock)
        model.collapse()
        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await drainMainActorTasks()

        XCTAssertEqual(model.phase, .collapsed)
    }

    func testReduceMotionUsesDeterministicShortTransition() async {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0))
        let model = DynamicIslandPresentationModel(clock: clock)
        model.setReduceMotion(true)

        model.toggleExpanded()
        await drainMainActorTasks()

        XCTAssertEqual(model.phase, .expanded)
        let history = await clock.sleepHistory()
        XCTAssertEqual(history, [.milliseconds(220)])
    }

    func testEveryStableStateCanBeCommandedWithoutAnimation() {
        let model = DynamicIslandPresentationModel()

        for state in NotchStableState.allCases {
            model.present(state, animated: false)
            XCTAssertEqual(model.visualState, state)
        }
    }

    func testPanelEscapeCommandCollapsesExpandedPresentation() async {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0))
        let model = DynamicIslandPresentationModel(phase: .expanded, clock: clock)
        let panelController = NotchiumPanelController(model: model)

        panelController.handleEscapeCommand()
        await drainMainActorTasks()

        XCTAssertEqual(model.phase, .collapsed)
    }
}
