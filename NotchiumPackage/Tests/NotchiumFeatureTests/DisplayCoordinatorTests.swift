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
