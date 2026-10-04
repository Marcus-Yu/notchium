import AppKit
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
final class Stage21EnvironmentProjectionTests: XCTestCase {
    func testMaximizedWindowAndAutoHiddenMenuBarAreNotFullscreenEvidence() {
        let display = builtInDisplay()
        for options in [NSApplication.PresentationOptions(), [.autoHideMenuBar, .autoHideDock]] {
            let evidence = AppKitDisplayEnvironmentSource.project(options: options,
                quartzFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)], pointerLocation: nil, displays: [display])
            XCTAssertFalse(evidence.isFullscreen)
            XCTAssertFalse(evidence.isPresentationLike)
            var state = DisplayPresentationState()
            state.rebuild([display], evidence: evidence)
            XCTAssertEqual(state.presentationContext, .normal)
        }
    }

    func testQuartzProjectionUsesPrimaryTopWithDisplaysAboveAndLeft() {
        let primary = builtInDisplay()
        let above = externalDisplay(id: 2, frame: CGRect(x: -1200, y: 982, width: 1200, height: 1920), primary: false)
        let evidence = AppKitDisplayEnvironmentSource.project(options: [.fullScreen, .autoHideMenuBar, .autoHideDock],
            quartzFrames: [CGRect(x: -1200, y: -1920, width: 1200, height: 1920)],
            pointerLocation: CGPoint(x: -600, y: 1500), displays: [primary, above])
        XCTAssertEqual(evidence.frontmostDisplayID, above.id)
        XCTAssertEqual(evidence.fullscreenDisplayID, above.id)
        XCTAssertTrue(evidence.isFullscreen)
        XCTAssertFalse(evidence.isPresentationLike)
    }

    func testPresentationRequiresStrongerOptionsAndMissingWindowEvidenceIsConservative() {
        let primary = builtInDisplay()
        let evidence = AppKitDisplayEnvironmentSource.project(options: [.hideMenuBar, .hideDock],
            quartzFrames: [CGRect(x: 0, y: 38, width: 1512, height: 944)], pointerLocation: nil, displays: [primary])
        XCTAssertTrue(evidence.isPresentationLike)
        XCTAssertEqual(evidence.fullscreenDisplayID, primary.id)
        let unavailable = AppKitDisplayEnvironmentSource.project(options: [.fullScreen], quartzFrames: [],
            pointerLocation: nil, displays: [primary])
        var state = DisplayPresentationState()
        state.rebuild([primary], evidence: unavailable)
        XCTAssertEqual(state.presentationContext, .normal, "No display-scoped inference from unavailable metadata")
    }
}
