import AppKit
import NotchiumCore
@testable import NotchiumDynamicIsland
import SwiftUI
import XCTest

@MainActor
final class Stage23ShellAccessibilityTests: XCTestCase {
    func testOnlyExpandedPanelCanReceiveKeyboardFocus() throws {
        let model = DynamicIslandPresentationModel(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
        let controller = NotchiumPanelController(model: model)
        defer { controller.hide() }
        let placement = NotchShellPlacement(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch)
        for state in [NotchStableState.collapsed, .hovered, .expanded, .collapsed] {
            model.present(state, animated: false)
            controller.reconcile(placement: placement, layout: NotchGeometryResolver.layout(for: placement, state: state),
                                 renderConfiguration: .init(reduceMotion: .on), animated: false)
            let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? NotchPanel }.first {
                $0.fileDropHandler === controller
            })
            XCTAssertEqual(panel.canBecomeKey, state == .expanded, "Keyboard eligibility must follow the presented surface")
            XCTAssertFalse(panel.isKeyWindow, "Passive reconciliation must not take focus")
        }
    }

}
