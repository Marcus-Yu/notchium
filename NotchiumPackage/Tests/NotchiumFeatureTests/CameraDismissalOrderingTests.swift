import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class CameraDismissalOrderingTests: XCTestCase {
    func testHoverExitCommitsClosingStateBeforeCameraTeardown() {
        let model = DynamicIslandPresentationModel(phase: .hovered,
            clock: TestAppClock(now: .now, automaticallyAdvances: false))
        let camera = DismissalCamera()
        model.cameraController = camera
        defer { camera.onClose = nil; model.reset() }
        camera.onClose = {
            XCTAssertEqual(model.visualState, .collapsed)
            XCTAssertEqual(model.surfaceState, .collapsed,
                           "Native teardown must not render the old hovered shell with its preview removed")
        }

        model.collapse()

        XCTAssertFalse(camera.isPreviewPresented)
        XCTAssertEqual(model.visualState, .collapsed)
    }

    func testReentryDuringCameraTeardownKeepsTheNewerOpenSession() {
        let model = DynamicIslandPresentationModel(phase: .hovered,
            clock: TestAppClock(now: .now, automaticallyAdvances: false))
        let camera = DismissalCamera()
        model.cameraController = camera
        defer { camera.onClose = nil; model.reset() }
        camera.onClose = {
            // A native view teardown can deliver another interaction before returning.
            model.present(.expanded, animated: false)
        }

        model.collapse()

        XCTAssertEqual(model.phase, .expanded, "The older exit must not overwrite a newer opening")
        XCTAssertFalse(camera.isPreviewPresented)
    }

    func testImmediateDismissalAndResetCommitBeforeCameraTeardown() {
        for reset in [false, true] {
            let model = DynamicIslandPresentationModel(phase: .hovered,
                clock: TestAppClock(now: .now, automaticallyAdvances: false))
            let camera = DismissalCamera()
            model.cameraController = camera
            camera.onClose = { XCTAssertEqual(model.visualState, .collapsed) }

            if reset { model.reset() }
            else { model.present(.collapsed, animated: false) }

            XCTAssertFalse(camera.isPreviewPresented)
            camera.onClose = nil
            model.reset()
        }
    }
}

@MainActor
private final class DismissalCamera: NotchCameraControlling {
    var isPreviewPresented = true
    var onClose: (() -> Void)?

    func togglePreview() { isPreviewPresented ? closePreview() : (isPreviewPresented = true) }
    func closePreview() {
        guard isPreviewPresented else { return }
        isPreviewPresented = false
        onClose?()
    }
    func preview() -> AnyView { AnyView(Color.black) }
}
