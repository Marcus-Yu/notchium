import Foundation
import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

final class TeleprompterGeometryTests: XCTestCase {
    func testReaderIsTwentyFivePercentLargerWithoutChangingOtherPages() {
        let standard = ExpandedNotchLayout.size
        let reader = ExpandedNotchLayout.size(for: .teleprompter)
        XCTAssertEqual(reader, CGSize(width: 655, height: 333))
        XCTAssertEqual(reader.width / standard.width, 1.25, accuracy: 0.001)
        XCTAssertEqual(reader.height / standard.height, 1.25, accuracy: 0.003)
        for page in NotchPage.allCases where page != .teleprompter {
            XCTAssertEqual(ExpandedNotchLayout.size(for: page), standard)
        }
    }

    func testReaderAndMinorActivityFitTheSameTopAnchoredPanelInEveryState() {
        let placements = [
            NotchShellPlacement(display: builtInDisplay(), mode: .physicalNotch),
            NotchShellPlacement(display: externalDisplay(frame: CGRect(x: -1920, y: 100, width: 1920, height: 1080)),
                                mode: .virtualPill)
        ]
        for placement in placements {
            let standard = NotchGeometryResolver.layout(for: placement, state: .expanded)
            for state in NotchStableState.allCases {
                let reader = NotchGeometryResolver.layout(for: placement, state: state,
                    expandedSize: ExpandedNotchLayout.teleprompterSize)
                XCTAssertEqual(reader.panelFrame, standard.panelFrame)
                XCTAssertEqual(reader.panelFrame.maxY, placement.display.frame.maxY)
                XCTAssertEqual(reader.panelFrame.midX, placement.display.frame.midX)
                XCTAssertTrue(reader.panelFrame.contains(reader.visibleSurfaceFrame))
                XCTAssertTrue(reader.panelFrame.contains(NotchExpandedMinorGeometry.frame(layout: reader)),
                              "The reader and existing 56pt activity extension must remain inside the host")
                if state == .collapsed {
                    XCTAssertEqual(reader.visibleSurfaceFrame, standard.collapsedVisibleFrame)
                } else {
                    XCTAssertEqual(reader.surfaceSize, ExpandedNotchLayout.teleprompterSize)
                    XCTAssertEqual(reader.visibleSurfaceFrame.size, ExpandedNotchLayout.teleprompterSize)
                }
            }
        }
    }

    @MainActor
    func testSelectingReaderReconcilesNativeHitRegionAndReturningRestoresStandardSize() async {
        let model = DynamicIslandPresentationModel(phase: .expanded,
            clock: TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false))
        let panel = GeometryRecordingPanel()
        let session = NotchDisplaySession(model: model, panel: panel)
        let placement = NotchShellPlacement(display: builtInDisplay(), mode: .physicalNotch)
        session.update(placement: placement, context: .normal, configuration: .automatic, animated: false)
        defer { session.stop() }
        let standard = panel.layouts.last!
        XCTAssertEqual(standard.surfaceSize, ExpandedNotchLayout.size)

        model.pageModel.selectedPage = .teleprompter
        await waitUntil { panel.layouts.last?.surfaceSize == ExpandedNotchLayout.teleprompterSize }
        let reader = panel.layouts.last!
        let lowerReadingPoint = CGPoint(x: reader.visibleSurfaceFrame.midX, y: reader.visibleSurfaceFrame.minY + 1)
        XCTAssertTrue(NotchHoverRegion.contains(lowerReadingPoint, in: reader.visibleSurfaceFrame))
        XCTAssertFalse(NotchHoverRegion.contains(lowerReadingPoint, in: standard.visibleSurfaceFrame))
        XCTAssertEqual(reader.panelFrame, standard.panelFrame, "Native hosting panel must not move or resize")

        model.pageModel.selectedPage = .calendar
        await waitUntil { panel.layouts.last?.surfaceSize == ExpandedNotchLayout.size }
        XCTAssertEqual(panel.layouts.last?.panelFrame, standard.panelFrame)
        XCTAssertEqual(panel.layouts.last?.visibleSurfaceFrame, standard.visibleSurfaceFrame)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected native page geometry did not reconcile")
    }
}

@MainActor
private final class GeometryRecordingPanel: NotchPanelControlling {
    var layouts: [NotchPanelLayout] = []
    func reconcile(placement: NotchShellPlacement, layout: NotchPanelLayout,
                   renderConfiguration: NotchShellRenderConfiguration, animated: Bool) { layouts.append(layout) }
    func hide() {}
    func orderFrontRegardless() {}
}
