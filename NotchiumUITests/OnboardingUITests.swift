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
        let resumedRequest = app.buttons["notchium.setup.request.calendar"]
        XCTAssertTrue(resumedRequest.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Get Started"].exists)
        // Synthetic permission statuses restart; saved onboarding progress does not.
        resumedRequest.click()
        XCTAssertTrue(app.staticTexts["Denied"].waitForExistence(timeout: 3))
        app.buttons["Review All"].click()
        XCTAssertTrue(app.buttons["notchium.setup.finish"].exists)
        XCTAssertTrue(app.buttons["notchium.setup.finish"].isEnabled)
        XCTAssertTrue(app.staticTexts["Denied"].exists)
        capture(app, "stage27b-denied-review")
        app.buttons["notchium.setup.finish"].click()
        verifyReadyOpenAndRelaunch(app)
    }

    func testEveryPermissionCanBeSkippedWithoutChoosingClipboardHistory() {
        let app = application(id: UUID())
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 8))
        app.buttons["Get Started"].click()
        app.buttons["Set Up Permissions"].click()

        let titles = ["Calendars", "Reminders", "Spotify Automation", "Camera", "System Audio Recording",
                      "Accessibility for Volume Keys", "Screenshot Folder", "Clipboard History",
                      "macOS Pasteboard Access", "Shelf & File Actions", "Apple Shortcuts", "System Focus Status",
                      "In-App Notifications", "Clipboard Encryption", "Caffeine & Closed-Lid Mode"]
        for (index, title) in titles.enumerated() {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 4), title)
            XCTAssertTrue(app.staticTexts["\(index + 1) of \(titles.count)"].exists, title)
            XCTAssertTrue(app.buttons["Continue"].isEnabled, title)
            if title == "Clipboard History" {
                XCTAssertTrue(app.buttons["notchium.setup.clipboard.enable"].exists)
                XCTAssertTrue(app.buttons["notchium.setup.clipboard.off"].exists)
                assertNoClipboardChoice(app)
            }
            app.buttons["Continue"].click()
        }

        XCTAssertTrue(app.staticTexts["Review your setup"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["Granted"].exists)
        XCTAssertFalse(app.staticTexts["Folder Selected"].exists)
        XCTAssertFalse(app.staticTexts["Exceptions reviewed"].exists)
        assertNoClipboardChoice(app)
        let finish = app.buttons["notchium.setup.finish"]
        XCTAssertTrue(finish.isEnabled)
        capture(app, "stage27b-all-permissions-skipped-review")
        finish.click()
        verifyReadyOpenAndRelaunch(app)
    }

    func testSpotifyDeniedExceptionCompletesSetupReadyAndRelaunches() {
        completeSetup(spotifyException: true)
    }

    func testCompleteSetupReadyAndTenRelaunches() {
        completeSetup(spotifyException: false)
    }

    private func completeSetup(spotifyException: Bool) {
        let app = application(id: UUID())
        if spotifyException { app.launchArguments.append("--notchium-setup-spotify-denied") }
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
                if permission == "spotify" && spotifyException {
                    XCTAssertTrue(app.staticTexts["Denied"].waitForExistence(timeout: 4))
                    app.buttons["notchium.setup.spotify.continueWithout"].click()
                    XCTAssertTrue(app.staticTexts["Denied"].exists)
                } else {
                    XCTAssertTrue(app.staticTexts[permission == "screenshots" ? "Folder Selected" : "Granted"].waitForExistence(timeout: 4))
                }
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
        verifyReadyOpenAndRelaunch(app, relaunches: 10)
    }

    private func verifyReadyOpenAndRelaunch(_ app: XCUIApplication, relaunches: Int = 1) {
        XCTAssertTrue(app.buttons["notchium.setup.open"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["You’re ready"].exists)
        XCTAssertFalse(app.buttons["notchium.setup.finish"].exists)
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
        for _ in 0..<relaunches {
            app.launch()
            XCTAssertTrue(app.buttons["notchium.page.home"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["Get Started"].exists)
            XCTAssertFalse(app.buttons["notchium.setup.finish"].exists)
            XCTAssertFalse(app.buttons["notchium.setup.open"].exists)
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
        XCTAssertTrue(app.buttons["notchium.setup.finish"].isEnabled)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        XCTAssertTrue(app.buttons["notchium.setup.finish"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["notchium.setup.finish"].isEnabled)
        XCTAssertFalse(app.buttons["Get Started"].exists)
        app.windows["notchium.onboarding"].buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        XCTAssertTrue(app.buttons["notchium.setup.finish"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["notchium.setup.finish"].isEnabled)
        app.typeKey(.return, modifierFlags: [])
        verifyReadyOpenAndRelaunch(app)
    }

    private func assertNoClipboardChoice(_ app: XCUIApplication) {
        XCTAssertFalse(app.staticTexts["Your choice: monitoring enabled after setup."].exists)
        XCTAssertFalse(app.staticTexts["Your choice: monitoring stays off."].exists)
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
