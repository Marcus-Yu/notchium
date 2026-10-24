import XCTest

/// Uses native pointer tracking around the mounted shell. Model-only tests cannot
/// establish that leaving a camera preview still reaches the panel's hover exit.
@MainActor
final class CameraHoverExitUITests: XCTestCase {
    func testCameraHoverExitAndReentryRemainInteractive() {
        exerciseCameraHoverExit(reduceMotion: "off")
    }

    func testCameraHoverExitAndReentryWithReducedMotionRemainInteractive() {
        exerciseCameraHoverExit(reduceMotion: "on")
    }

    private func exerciseCameraHoverExit(reduceMotion: String) {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--notchium-stage11-fixture", "--notchium-quality-fixture",
            "--notchium-pointer-hover-fixture",
            "--notchium-display", "builtInMock", "--notchium-surface", "physical",
            "--notchium-presentation", "collapsed", "--notchium-appearance", "dark",
            "--notchium-reduce-motion", reduceMotion,
        ]
        app.launch()
        defer { app.terminate() }
        app.activate()
        let shell = element("notchium.shell", in: app)
        guard assertExists(shell, app: app, name: "camera-hover-\(reduceMotion)-launch") else { return }

        // Both coordinates belong to the same 740×322 shell root. The entry is
        // just below the physical cutout; the exit is below the expanded surface.
        let entry = shell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.125))
        let outside = shell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
        outside.hover()
        guard assertState("collapsed", in: app, name: "camera-hover-\(reduceMotion)-initial") else { return }

        for cycle in 1...3 {
            let prefix = "camera-hover-\(reduceMotion)-\(cycle)"
            entry.hover()
            guard assertState("hovered", in: app, name: "\(prefix)-open") else { return }
            let mirror = element("notchium.shell.camera", in: app)
            guard assertHittable(mirror, app: app, name: "\(prefix)-mirror-off") else { return }
            XCTAssertEqual(mirror.value as? String, "Off", app.debugDescription)
            mirror.click()
            let cameraClose = element("notchium.camera.close", in: app)
            guard assertExists(cameraClose, app: app, name: "\(prefix)-preview") else { return }

            // The fixture grants access in-process; it never opens the system
            // consent alert or connects to a physical camera.
            let allow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Allow Camera'")).firstMatch
            if allow.exists {
                allow.click()
            }
            guard assertHittable(cameraClose, app: app, name: "\(prefix)-camera-open") else { return }
            XCTAssertEqual(mirror.value as? String, "Preview open", app.debugDescription)

            // Exit by moving the pointer, without Escape, a close action, or a
            // synthetic model event. This is the reported failing interaction.
            outside.hover()
            guard assertState("collapsed", in: app, name: "\(prefix)-after-exit") else { return }
            entry.hover()
            guard assertState("hovered", in: app, name: "\(prefix)-reopened") else { return }

            let home = app.buttons["notchium.page.home"].firstMatch
            let close = element("notchium.shell.close", in: app)
            guard assertHittable(home, app: app, name: "\(prefix)-header-restored"),
                  assertHittable(close, app: app, name: "\(prefix)-close-restored"),
                  assertHittable(mirror, app: app, name: "\(prefix)-mirror-restored") else { return }
            XCTAssertEqual(mirror.value as? String, "Off", "Leaving the shell must close the camera preview")
            XCTAssertFalse(cameraClose.exists, app.debugDescription)

            // Confirm the returning header can actually dismiss the shell too.
            close.click()
            outside.hover()
            guard assertState("collapsed", in: app, name: "\(prefix)-closed-again") else { return }
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func assertState(_ state: String, in app: XCUIApplication, name: String) -> Bool {
        assertExists(element("notchium.shell.state.\(state)", in: app), app: app, name: name)
    }

    private func assertExists(_ element: XCUIElement, app: XCUIApplication, name: String) -> Bool {
        let exists = element.waitForExistence(timeout: 5)
        capture(name)
        XCTAssertTrue(exists, app.debugDescription)
        return exists
    }

    private func assertHittable(_ element: XCUIElement, app: XCUIApplication, name: String) -> Bool {
        let ready = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)], timeout: 5) == .completed
        capture(name)
        XCTAssertTrue(ready, app.debugDescription)
        return ready
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
