import XCTest

@MainActor final class OnboardingUITests: XCTestCase {
    func testFirstLaunchInterruptedSetupAndDeniedReview() {
        let app = application(id: UUID(), denied: true)
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["notchium.page.home"].exists)
        capture(app, "stage27b-welcome")
        app.buttons["Get Started"].click()
        XCTAssertTrue(app.staticTexts["Your integrations, in one place"].exists)
        capture(app, "stage27b-overview")
        app.buttons["Set Up Permissions"].click()
        app.buttons["notchium.setup.request.calendar"].click()
        XCTAssertTrue(app.staticTexts["Denied"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open System Settings"].exists)
        capture(app, "stage27b-denied")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Open System Settings"].waitForExistence(timeout: 8)
                      || app.buttons["notchium.setup.request.calendar"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Get Started"].exists)
        app.buttons["Review All"].click()
        XCTAssertTrue(app.buttons["notchium.setup.finish"].exists)
        XCTAssertFalse(app.buttons["notchium.setup.finish"].isEnabled)
        capture(app, "stage27b-incomplete-review")
    }

    func testCompleteSetupReadyAndTenRelaunches() {
        let app = application(id: UUID())
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 8))
        app.buttons["Get Started"].click()
        app.buttons["Set Up Permissions"].click()
        let grantable = ["calendar", "reminders", "spotify", "camera", "volumeKeys", "screenshots"]
        let all = ["calendar", "reminders", "spotify", "camera", "systemAudio", "volumeKeys", "screenshots",
                   "clipboard", "clipboardAccess", "files", "shortcuts", "focus", "notifications", "keychain", "closedLid"]
        for permission in all {
            if grantable.contains(permission) {
                let request = app.buttons["notchium.setup.request.\(permission)"]
                XCTAssertTrue(request.waitForExistence(timeout: 4), permission)
                request.click()
                XCTAssertTrue(app.staticTexts[permission == "screenshots" ? "Folder Selected" : "Granted"].waitForExistence(timeout: 4))
            } else if permission == "clipboard" {
                app.buttons["notchium.setup.clipboard.off"].click()
            } else {
                let acknowledge = app.buttons["notchium.setup.acknowledge"]
                XCTAssertTrue(acknowledge.waitForExistence(timeout: 3), permission)
                acknowledge.click()
            }
            app.buttons["Continue"].click()
        }
        let finish = app.buttons["notchium.setup.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 4))
        XCTAssertTrue(finish.isEnabled)
        capture(app, "stage27b-complete-review")
        finish.click()
        XCTAssertTrue(app.buttons["notchium.setup.open"].waitForExistence(timeout: 4))
        capture(app, "stage27b-ready")
        XCTAssertFalse(app.buttons["notchium.page.home"].exists)
        // Normal Settings must stay gated until Ready's Open action starts features.
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Complete Notchium setup to continue."].waitForExistence(timeout: 4))
        app.windows["com_apple_SwiftUI_Settings_window"].buttons[XCUIIdentifierCloseWindow].click()
        app.buttons["notchium.setup.open"].click()
        let shell = app.descendants(matching: .any)["notchium.shell"].firstMatch
        XCTAssertTrue(shell.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["notchium.setup.open"].exists)
        if !app.buttons["notchium.page.home"].exists {
            app.activate()
            shell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.125)).click()
        }
        XCTAssertTrue(app.buttons["notchium.page.home"].waitForExistence(timeout: 8))
        app.terminate()
        for _ in 0..<10 {
            app.launch()
            XCTAssertTrue(app.buttons["notchium.page.home"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["Get Started"].exists)
            app.terminate()
        }
    }

    func testKeyboardNavigationQuitAndWindowCloseResumeWithoutCompletion() {
        let app = application(id: UUID())
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 8))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Set Up Permissions"].waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["notchium.setup.request.calendar"].waitForExistence(timeout: 3))
        app.buttons["Review All"].click()
        XCTAssertFalse(app.buttons["notchium.setup.finish"].isEnabled)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        XCTAssertTrue(app.buttons["notchium.setup.finish"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["notchium.setup.finish"].isEnabled)
        XCTAssertFalse(app.buttons["Get Started"].exists)
        app.windows["notchium.onboarding"].buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        XCTAssertTrue(app.buttons["notchium.setup.finish"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["notchium.setup.finish"].isEnabled)
    }

    private func application(id: UUID, denied: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--notchium-onboarding-fixture", id.uuidString,
                               "--notchium-display", "builtInMock", "--notchium-surface", "physical",
                               "--notchium-presentation", "expanded", "--notchium-appearance", "dark"]
        if denied { app.launchArguments.append("--notchium-setup-denied") }
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
