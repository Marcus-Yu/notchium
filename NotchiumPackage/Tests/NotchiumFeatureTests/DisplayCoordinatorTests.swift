import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
private final class MockDisplaySource: NotchiumDisplaySnapshotting {
    var displays: [NotchiumDisplaySnapshot]

    init(displays: [NotchiumDisplaySnapshot]) {
        self.displays = displays
    }

    func snapshots() -> [NotchiumDisplaySnapshot] {
        displays
    }
}

@MainActor
private final class MockPanelController: NotchPanelControlling {
    private(set) var placement: NotchShellPlacement?
    private(set) var layout: NotchPanelLayout?
    private(set) var renderConfiguration: NotchShellRenderConfiguration?
    private(set) var reconcileCount = 0
    private(set) var orderFrontRegardlessCount = 0
    private(set) var hideCount = 0
    var onOrderFront: (() -> Void)?

    func reconcile(
        placement: NotchShellPlacement,
        layout: NotchPanelLayout,
        renderConfiguration: NotchShellRenderConfiguration,
        animated: Bool
    ) {
        self.placement = placement
        self.layout = layout
        self.renderConfiguration = renderConfiguration
        reconcileCount += 1
    }

    func orderFrontRegardless() {
        onOrderFront?()
        orderFrontRegardlessCount += 1
    }

    func hide() {
        hideCount += 1
        placement = nil
        layout = nil
        renderConfiguration = nil
    }
}

@MainActor
final class DisplayCoordinatorTests: XCTestCase {
    func testSpaceChangeCollapsesHoveredAndPinnedStatesBeforeReassertingPanel() async {
        for state in [NotchStableState.hovered, .expanded] {
            let source = MockDisplaySource(displays: [builtInDisplay()])
            let panel = MockPanelController()
            let clock = ControlledAppClock()
            let coordinator = makeCoordinator(source: source, panel: panel, clock: clock)
            coordinator.start()
            let model = coordinator.presentationModel
            model.present(state, animated: false)
            model.setHovered(true)
            await drainMainActorTasks()
            let frame = panel.layout?.panelFrame
            let hideCount = panel.hideCount
            panel.onOrderFront = {
                XCTAssertEqual(model.phase, .transitioning(from: state, to: .collapsed))
            }

            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
            )

            XCTAssertEqual(model.phase, .transitioning(from: state, to: .collapsed))
            XCTAssertEqual(panel.orderFrontRegardlessCount, 1)
            await waitForPendingSleep(clock)
            await clock.releaseAll()
            await drainMainActorTasks()
            XCTAssertEqual(model.phase, .collapsed)
            XCTAssertEqual(panel.layout?.panelFrame, frame)
            XCTAssertEqual(panel.hideCount, hideCount)

            // The pointer staying inside cannot re-trigger hover after a swipe.
            model.setHovered(true)
            await clock.releaseAll()
            await drainMainActorTasks()
            XCTAssertEqual(model.phase, .collapsed)

            // A deliberate click still opens and pins normally.
            model.toggleExpanded()
            XCTAssertEqual(model.visualState, .expanded)
            coordinator.stop()
        }
    }

    func testSpaceChangeLeavesPassiveStateAndPanelUnchanged() {
        let source = MockDisplaySource(displays: [builtInDisplay()])
        let panel = MockPanelController()
        let coordinator = makeCoordinator(source: source, panel: panel)
        coordinator.start()
        defer { coordinator.stop() }

        let reconcileCount = panel.reconcileCount

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        XCTAssertEqual(panel.orderFrontRegardlessCount, 1)
        XCTAssertEqual(panel.reconcileCount, reconcileCount)
        XCTAssertEqual(coordinator.presentationModel.phase, .collapsed)
    }

    func testSpaceChangeCancelsPendingHoverUntilFreshEntry() async {
        let source = MockDisplaySource(displays: [builtInDisplay()])
        let panel = MockPanelController()
        let clock = ControlledAppClock()
        let coordinator = makeCoordinator(source: source, panel: panel, clock: clock)
        coordinator.start()
        defer { coordinator.stop() }
        let model = coordinator.presentationModel
        model.setHovered(true)
        await waitForPendingSleep(clock)

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .collapsed)
        model.setHovered(true)
        await drainMainActorTasks()
        let pendingCount = await clock.pendingCount()
        XCTAssertEqual(pendingCount, 0)

        model.setHovered(false)
        model.setHovered(true)
        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.visualState, .hovered)
    }

    func testSpaceChangeDoesNotResurrectShellWithoutBuiltInDisplay() {
        let source = MockDisplaySource(displays: [builtInDisplay()])
        let panel = MockPanelController()
        let coordinator = makeCoordinator(source: source, panel: panel)
        coordinator.start()
        defer { coordinator.stop() }
        source.displays = [externalDisplay()]
        coordinator.refreshDisplayConfiguration()
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        XCTAssertNil(panel.placement)
        XCTAssertEqual(panel.orderFrontRegardlessCount, 0)
    }

    func testBuiltInArrivalEnablesShellAndCollapses() {
        let source = MockDisplaySource(displays: [externalDisplay()])
        let panel = MockPanelController()
        let coordinator = makeCoordinator(source: source, panel: panel)
        coordinator.start()
        defer { coordinator.stop() }

        XCTAssertNil(panel.placement)
        coordinator.presentationModel.present(.expanded, animated: false)

        source.displays = [externalDisplay(), builtInDisplay(primary: false)]
        coordinator.refreshDisplayConfiguration()

        XCTAssertEqual(coordinator.presentationModel.phase, .collapsed)
        XCTAssertEqual(panel.placement?.mode, .physicalNotch)
        XCTAssertEqual(panel.placement?.display.id, NotchiumDisplayID(rawValue: 1))
    }

    func testNotchDisappearanceHidesShell() {
        let source = MockDisplaySource(displays: [builtInDisplay(), externalDisplay(primary: false)])
        let panel = MockPanelController()
        let coordinator = makeCoordinator(source: source, panel: panel)
        coordinator.start()
        defer { coordinator.stop() }

        source.displays = [externalDisplay(primary: true)]
        coordinator.refreshDisplayConfiguration()

        XCTAssertNil(panel.placement)
    }

    func testZeroDisplaysHidesPanelAndLeavesNoPlacement() {
        let source = MockDisplaySource(displays: [externalDisplay()])
        let panel = MockPanelController()
        let coordinator = makeCoordinator(source: source, panel: panel)
        coordinator.start()
        defer { coordinator.stop() }

        source.displays = []
        coordinator.refreshDisplayConfiguration()

        XCTAssertNil(coordinator.shellPlacement)
        XCTAssertGreaterThan(panel.hideCount, 0)
    }

    func testDebugReconciliationUsesMockPlacementAndAccessibilityOverrides() {
        let source = MockDisplaySource(displays: [])
        let panel = MockPanelController()
        let debugModel = NotchShellDebugModel(arguments: [])
        debugModel.displaySource = .builtInMock
        debugModel.surfaceMode = .virtual
        debugModel.reduceMotion = .on
        debugModel.reduceTransparency = .on
        debugModel.showNotchGeometry = true
        let coordinator = makeCoordinator(
            source: source,
            panel: panel,
            debugModel: debugModel
        )
        coordinator.start()
        defer { coordinator.stop() }

        XCTAssertEqual(panel.placement?.mode, .virtualPill)
        XCTAssertEqual(panel.renderConfiguration?.reduceMotion, .on)
        XCTAssertEqual(panel.renderConfiguration?.reduceTransparency, .on)
        XCTAssertEqual(panel.renderConfiguration?.showsGeometryOverlay, true)
        XCTAssertEqual(debugModel.runtimeLayout, panel.layout)
        XCTAssertEqual(debugModel.runtimePlacement, panel.placement)
    }

    func testExternalDebugFixtureUsesLiveGlobalFrameAndRetinaScale() {
        let liveDisplay = NotchiumDisplaySnapshot(
            id: NotchiumDisplayID(rawValue: 99),
            name: "Live offset display",
            frame: CGRect(x: 1512, y: -120, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 1512, y: -80, width: 1728, height: 1077),
            isBuiltIn: false,
            isPrimary: true,
            backingScaleFactor: 2
        )
        let source = MockDisplaySource(displays: [liveDisplay])
        let panel = MockPanelController()
        let debugModel = NotchShellDebugModel(arguments: [])
        debugModel.displaySource = .externalMock
        let coordinator = makeCoordinator(source: source, panel: panel, debugModel: debugModel)
        coordinator.start()
        defer { coordinator.stop() }

        XCTAssertNil(panel.placement)
    }

    func testBuiltInDebugFixtureProjectsNotchGeometryOntoLiveFrame() {
        let liveDisplay = externalDisplay(
            id: 77,
            frame: CGRect(x: -1728, y: 96, width: 1728, height: 1117)
        )
        let source = MockDisplaySource(displays: [liveDisplay])
        let panel = MockPanelController()
        let debugModel = NotchShellDebugModel(arguments: [])
        debugModel.displaySource = .builtInMock
        let coordinator = makeCoordinator(source: source, panel: panel, debugModel: debugModel)
        coordinator.start()
        defer { coordinator.stop() }

        XCTAssertEqual(panel.placement?.mode, .physicalNotch)
        XCTAssertEqual(panel.placement?.display.frame, liveDisplay.frame)
        XCTAssertEqual(panel.placement?.display.physicalNotchGap?.midX, liveDisplay.frame.midX)
        XCTAssertEqual(panel.layout?.panelFrame.maxY, liveDisplay.frame.maxY)
        XCTAssertEqual(panel.layout?.panelFrame.midX, liveDisplay.frame.midX)
    }

    private func makeCoordinator(
        source: MockDisplaySource,
        panel: MockPanelController,
        debugModel: NotchShellDebugModel = NotchShellDebugModel(arguments: []),
        clock: any AppClock = TestAppClock(now: Date(timeIntervalSince1970: 0))
    ) -> NotchiumDisplayCoordinator {
        NotchiumDisplayCoordinator(
            clock: clock,
            displaySource: source,
            panelControllerFactory: { _ in panel },
            debugModel: debugModel
        )
    }
}
