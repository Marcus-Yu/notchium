import AppKit
import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
final class DynamicIslandPresentationTests: XCTestCase {
    func testAudioHUDUpdatesInPlaceAndDoesNotTakeOverExpandedPage() async {
        let clock = TestAppClock(
            now: Date(timeIntervalSince1970: 0),
            automaticallyAdvances: false
        )
        let model = DynamicIslandPresentationModel(clock: clock)
        let first = NotchAudioHUD(kind: .volume, deviceName: "Speakers", volume: 0.4, isMuted: false)
        let repeatEvent = NotchAudioHUD(kind: .volume, deviceName: "Speakers", volume: 0.5, isMuted: false)

        model.showAudioHUD(first)
        XCTAssertEqual(model.audioHUD, first)
        model.showAudioHUD(repeatEvent)
        XCTAssertEqual(model.audioHUD, repeatEvent)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(1250))
        await drainMainActorTasks()
        XCTAssertNil(model.audioHUD)

        model.present(.expanded, animated: false)
        model.showAudioHUD(first)
        XCTAssertEqual(model.audioHUD, first)
        XCTAssertEqual(model.presentationState, .expanded)
        XCTAssertEqual(model.visualState, .expanded)
    }

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
        XCTAssertTrue(history.contains(.milliseconds(200)))
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

    func testPinnedStateIgnoresHoverExit() async {
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

        XCTAssertEqual(model.phase, .expanded)
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
        XCTAssertEqual(history, [.milliseconds(400)])
    }

    func testHoverReentryCancelsPendingCollapse() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        model.setHovered(true)

        model.setHovered(false)
        await waitForPendingSleep(clock)
        model.setHovered(true)
        await clock.releaseAll()
        await drainMainActorTasks()

        XCTAssertEqual(model.visualState, .hovered)
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

    func testClosingUsesSoftShorterDuration() async {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0))
        let model = DynamicIslandPresentationModel(phase: .expanded, clock: clock)
        model.collapse()
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .collapsed)
        let history = await clock.sleepHistory()
        XCTAssertEqual(history, [.milliseconds(400)])
    }

    func testRapidReversalsSettleAtLatestTarget() async {
        for finalExpanded in [false, true] {
            let clock = ControlledAppClock()
            let model = DynamicIslandPresentationModel(clock: clock)
            for _ in 0..<12 {
                model.toggleExpanded()
                await waitForPendingSleep(clock)
            }
            model.setExpanded(finalExpanded)
            await waitForPendingSleep(clock)
            await clock.releaseAll()
            await drainMainActorTasks()
            XCTAssertEqual(model.phase, finalExpanded ? .expanded : .collapsed)
            XCTAssertEqual(model.surfaceState, finalExpanded ? .expanded : .collapsed)
        }
    }

    func testReduceMotionUsesDeterministicShortTransition() async {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0))
        let model = DynamicIslandPresentationModel(clock: clock)
        model.setReduceMotion(true)

        model.toggleExpanded()
        await drainMainActorTasks()

        XCTAssertEqual(model.phase, .expanded)
        let history = await clock.sleepHistory()
        XCTAssertEqual(history, [.milliseconds(120)])
    }

    func testEveryStableStateCanBeCommandedWithoutAnimation() {
        let model = DynamicIslandPresentationModel()

        for state in NotchStableState.allCases {
            model.present(state, animated: false)
            XCTAssertEqual(model.visualState, state)
        }
    }

    func testRepeatedPointerMovementDoesNotRestartEntryDelay() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(clock: clock)
        model.setHovered(true)
        await waitForPendingSleep(clock)
        for _ in 0..<20 { model.setHovered(true) }
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.visualState, .hovered)
    }

    func testPinCancelsPendingHoverCollapse() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        model.setHovered(true)
        model.setHovered(false)
        await waitForPendingSleep(clock)
        model.toggleExpanded()
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.visualState, .expanded)
    }

    func testAuxiliaryInteractionHoldsHoverOpenUntilItCloses() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)

        model.setAuxiliaryInteractionPresented(true)
        model.setHovered(true)
        model.setHovered(false)
        await drainMainActorTasks()

        XCTAssertTrue(model.isAuxiliaryInteractionPresented)
        XCTAssertEqual(model.visualState, .hovered)
        let pendingWhileOpen = await clock.pendingCount()
        XCTAssertEqual(pendingWhileOpen, 0)

        model.setAuxiliaryInteractionPresented(false)
        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await drainMainActorTasks()
        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await drainMainActorTasks()

        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        XCTAssertEqual(model.visualState, .collapsed)
    }

    func testPanelResignKeyCannotCollapseDuringAuxiliaryInteraction() {
        let model = DynamicIslandPresentationModel(phase: .expanded)
        let controller = NotchiumPanelController(model: model)
        defer { controller.hide() }

        model.setAuxiliaryInteractionPresented(true)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        XCTAssertEqual(model.visualState, .expanded)

        model.setAuxiliaryInteractionPresented(false)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        XCTAssertEqual(model.visualState, .collapsed)
    }

    func testAuxiliaryActionClickIsConsumedAcrossEitherAppKitCallbackOrder() {
        let clickBeforeClose = DynamicIslandPresentationModel(phase: .expanded)
        clickBeforeClose.setAuxiliaryInteractionPresented(true)
        XCTAssertTrue(clickBeforeClose.consumePointerClickForAuxiliaryInteraction())
        clickBeforeClose.endAuxiliaryInteraction(actionSelected: true)
        XCTAssertFalse(clickBeforeClose.consumePointerClickForAuxiliaryInteraction())

        let clickAfterClose = DynamicIslandPresentationModel(phase: .expanded)
        clickAfterClose.setAuxiliaryInteractionPresented(true)
        clickAfterClose.endAuxiliaryInteraction(actionSelected: true)
        XCTAssertTrue(clickAfterClose.consumePointerClickForAuxiliaryInteraction())
        XCTAssertFalse(clickAfterClose.consumePointerClickForAuxiliaryInteraction())
    }

    func testSwipeOverlayNeverInterceptsPointerHitTesting() {
        let view = NotchPageSwipeSurface.SwipeView(model: NotchPageModel())
        view.frame = CGRect(x: 0, y: 0, width: 450, height: 140)
        XCTAssertNil(view.hitTest(CGPoint(x: 200, y: 80)))
    }

    func testPanelClickPinsTogglesAndDismissesOutside() {
        let model = DynamicIslandPresentationModel(clock: ControlledAppClock())
        let controller = NotchiumPanelController(model: model)
        defer { controller.hide() }
        let placement = NotchShellPlacement(display: builtInDisplay(), mode: .physicalNotch)
        func reconcile() {
            controller.reconcile(
                placement: placement,
                layout: NotchGeometryResolver.layout(for: placement, state: model.visualState),
                renderConfiguration: .automatic,
                animated: false
            )
        }
        let point = CGPoint(x: 756, y: 980)
        reconcile()
        controller.handleClick(at: point)
        XCTAssertEqual(model.visualState, .expanded)
        reconcile()
        controller.handleClick(at: CGPoint(x: 756, y: 900))
        XCTAssertEqual(model.visualState, .expanded) // Content clicks must reach buttons.
        controller.handleClick(at: point)
        XCTAssertEqual(model.visualState, .collapsed)
        reconcile()
        controller.handleClick(at: point)
        reconcile()
        controller.handleClick(at: CGPoint(x: 0, y: 100))
        XCTAssertEqual(model.visualState, .collapsed)
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
