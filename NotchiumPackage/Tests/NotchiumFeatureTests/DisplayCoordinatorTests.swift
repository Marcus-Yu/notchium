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
    private(set) var hideCount = 0

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

    func hide() {
        hideCount += 1
    }
}

@MainActor
final class DisplayCoordinatorTests: XCTestCase {
    func testHotPlugMovesFromVirtualPillToBuiltInNotchAndCollapses() {
        let source = MockDisplaySource(displays: [externalDisplay()])
        let panel = MockPanelController()
        let coordinator = makeCoordinator(source: source, panel: panel)
        coordinator.start()
        defer { coordinator.stop() }

        XCTAssertEqual(panel.placement?.mode, .virtualPill)
        coordinator.presentationModel.present(.expanded, animated: false)

        source.displays = [externalDisplay(), builtInDisplay(primary: false)]
        coordinator.refreshDisplayConfiguration()

        XCTAssertEqual(coordinator.presentationModel.phase, .collapsed)
        XCTAssertEqual(panel.placement?.mode, .physicalNotch)
        XCTAssertEqual(panel.placement?.display.id, NotchiumDisplayID(rawValue: 1))
    }

    func testNotchDisappearanceFallsBackToPrimaryVirtualPill() {
        let source = MockDisplaySource(displays: [builtInDisplay(), externalDisplay(primary: false)])
        let panel = MockPanelController()
        let coordinator = makeCoordinator(source: source, panel: panel)
        coordinator.start()
        defer { coordinator.stop() }

        source.displays = [externalDisplay(primary: true)]
        coordinator.refreshDisplayConfiguration()

        XCTAssertEqual(panel.placement?.mode, .virtualPill)
        XCTAssertEqual(panel.placement?.display.id, NotchiumDisplayID(rawValue: 2))
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

        XCTAssertEqual(panel.placement?.display.frame, liveDisplay.frame)
        XCTAssertEqual(panel.placement?.display.visibleFrame, liveDisplay.visibleFrame)
        XCTAssertEqual(panel.placement?.display.backingScaleFactor, 2)
        XCTAssertEqual(panel.layout?.panelFrame.maxY, liveDisplay.frame.maxY)
        XCTAssertEqual(panel.layout?.panelFrame.midX, liveDisplay.frame.midX)
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
        debugModel: NotchShellDebugModel = NotchShellDebugModel(arguments: [])
    ) -> NotchiumDisplayCoordinator {
        NotchiumDisplayCoordinator(
            clock: TestAppClock(now: Date(timeIntervalSince1970: 0)),
            displaySource: source,
            panelControllerFactory: { _ in panel },
            debugModel: debugModel
        )
    }
}
