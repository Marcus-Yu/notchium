import AppKit
import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
final class SpaceTransitionTests: XCTestCase {
    func testSpaceChangeDuringHoverExitGraceImmediatelyCollapsesAndCancelsOldTimers() async {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        defer { model.reset() }
        model.setHovered(true)
        model.present(.hovered, animated: false)
        model.pageModel.selectedPage = .shelf
        model.setHovered(false)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(300))
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .hovered, "The pointer has left, but the exit grace is still active")

        model.prepareForSystemTransition()

        XCTAssertEqual(model.phase, .collapsed, "The destination Space must never show the old expanded surface")
        await clock.advance(by: .seconds(1))
        await drainMainActorTasks()
        await clock.advance(by: .seconds(1))
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .collapsed, "Neither an old hover task nor transition completion can reopen it")
    }

    func testSpaceChangeKeepsHoveredPageOpenWhilePointerIsInsideThenNormalExitStillCloses() async {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        defer { model.reset() }
        model.setHovered(true)
        model.pageModel.selectedPage = .calendar

        model.prepareForSystemTransition()
        await clock.advance(by: .seconds(1))
        await drainMainActorTasks()

        XCTAssertEqual(model.phase, .hovered)
        XCTAssertEqual(model.pageModel.selectedPage, .calendar)
        model.setHovered(false)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(499))
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .hovered, "A real exit after the swipe retains its normal grace")
        await clock.advance(by: .milliseconds(1))
        await waitUntil { model.visualState == .collapsed }
        XCTAssertEqual(model.visualState, .collapsed)
    }

    func testSpaceChangeCancelsHoverEntryBeforeItCanOpenTheDestinationSpace() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(clock: clock)
        defer { model.reset() }
        model.setHovered(true)
        await waitForPendingSleep(clock)

        model.prepareForSystemTransition()
        await clock.releaseAll()
        await drainMainActorTasks()
        await clock.releaseAll()
        await drainMainActorTasks()

        XCTAssertEqual(model.phase, .collapsed)
    }

    func testSpaceChangeSettlesAnAlreadyClosingSurfaceImmediately() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        defer { model.reset() }
        model.collapse()
        await waitForPendingSleep(clock)
        XCTAssertEqual(model.phase, .transitioning(from: .hovered, to: .collapsed))
        let revision = model.systemTransitionRevision

        model.prepareForSystemTransition()

        XCTAssertEqual(model.phase, .collapsed)
        XCTAssertGreaterThan(model.systemTransitionRevision, revision,
                             "The surface must be told to settle even though its target was already collapsed")
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .collapsed)
    }

    func testRepeatedSpaceChangesPreservePinnedSessionAndSelectedPage() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .expanded, clock: clock)
        defer { model.reset() }
        model.pageModel.selectedPage = .pomodoro
        for _ in 0..<10 {
            model.setHovered(true)
            model.setHovered(false)
            model.prepareForSystemTransition()
            await clock.releaseAll()
            await drainMainActorTasks()
            XCTAssertEqual(model.phase, .expanded)
            XCTAssertEqual(model.pageModel.selectedPage, .pomodoro)
        }
    }

    func testSpaceChangesPreserveAuxiliaryAndReturningSystemPresentationSessions() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        defer { model.reset() }
        model.pageModel.selectedPage = .shelf
        model.setAuxiliaryInteractionPresented(true, source: "space-transition-test")

        model.prepareForSystemTransition()
        await clock.releaseAll()
        await drainMainActorTasks()

        XCTAssertTrue(model.isAuxiliaryInteractionPresented)
        XCTAssertEqual(model.phase, .hovered)
        XCTAssertEqual(model.pageModel.selectedPage, .shelf)
        model.endAuxiliaryInteraction(actionSelected: false, source: "space-transition-test",
                                      returnsToOpenSession: true)
        XCTAssertTrue(model.isHeldAfterSystemPresentation)
        model.prepareForSystemTransition()
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .hovered)
        XCTAssertEqual(model.pageModel.selectedPage, .shelf)
    }

    func testPanelIsAlreadyCollapsedWhenReassertedOnTheDestinationSpace() async {
        let clock = ControlledAppClock()
        let panel = SpaceTransitionPanel()
        let coordinator = NotchiumDisplayCoordinator(clock: clock, displaySource: SpaceTransitionDisplays(),
                                                     panelControllerFactory: { _ in panel })
        coordinator.start()
        defer { coordinator.stop() }
        let model = coordinator.presentationModel
        model.setHovered(true)
        model.present(.hovered, animated: false)
        await drainMainActorTasks()
        XCTAssertEqual(panel.layout?.surfaceSize, NotchGeometryResolver.expandedNotchSize)
        model.setHovered(false)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(model.phase, .collapsed)
        for _ in 0..<10_000 where panel.orderedLayouts.isEmpty {
            await clock.releaseAll()
            await Task.yield()
        }
        let placement = NotchShellPlacement(display: builtInDisplay(), mode: .physicalNotch)
        let collapsedLayout = NotchGeometryResolver.layout(for: placement, state: .collapsed)
        XCTAssertEqual(panel.orderedLayouts.count, 1)
        XCTAssertEqual(panel.orderedLayouts.first?.visibleSurfaceFrame, collapsedLayout.visibleSurfaceFrame,
                       "Reasserting the panel must use the collapsed layout on its first visible frame")
    }
}

@MainActor
private final class SpaceTransitionDisplays: NotchiumDisplaySnapshotting {
    func snapshots() -> [NotchiumDisplaySnapshot] { [builtInDisplay()] }
}

@MainActor
private final class SpaceTransitionPanel: NotchPanelControlling {
    var layout: NotchPanelLayout?
    var orderedLayouts: [NotchPanelLayout] = []

    func reconcile(placement: NotchShellPlacement, layout: NotchPanelLayout,
                   renderConfiguration: NotchShellRenderConfiguration, animated: Bool) {
        self.layout = layout
    }

    func orderFrontRegardless() {
        if let layout { orderedLayouts.append(layout) }
    }

    func hide() { layout = nil }
}
