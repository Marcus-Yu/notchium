import AppKit
import XCTest

@MainActor
final class NotchiumUITests: XCTestCase {
    func testMirrorValueDescribesPreviewBeforeCameraPermission() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(display: "builtInMock", surface: "physical",
            presentation: "expanded", appearance: "dark") + ["--notchium-quality-fixture"]
        app.launch()
        XCTAssertTrue(waitForState("expanded", in: app, timeout: 5), app.debugDescription)
        let mirror = shellElement("notchium.shell.camera", in: app)
        XCTAssertTrue(mirror.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(mirror.value as? String, "Off")
        mirror.click()
        let permission = app.buttons.matching(NSPredicate(
            format: "label CONTAINS 'Notchium needs camera access'")).firstMatch
        XCTAssertTrue(permission.waitForExistence(timeout: 3))
        XCTAssertEqual(mirror.value as? String, "Preview open",
                       "An open permission screen must not announce that the camera is running")
        XCTAssertTrue(mirror.isSelected)
        shellElement("notchium.camera.close", in: app).click()
        XCTAssertEqual(mirror.value as? String, "Off")
        XCTAssertFalse(mirror.isSelected)
    }

    func testCaffeineKeyboardActivationAndEscape() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(display: "builtInMock", surface: "physical",
            presentation: "expanded", appearance: "dark")
        app.launch()
        let caffeine = shellElement("notchium.shell.caffeine", in: app)
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        caffeine.click()
        XCTAssertTrue(waitForCaffeine("Keeping Mac and display awake", element: caffeine))
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(waitForCaffeine("Off", element: caffeine))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForCaffeine("Keeping Mac and display awake", element: caffeine))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 3))
    }

    func testSearchClearUsesItsPaddedTarget() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(display: "builtInMock", surface: "physical",
            presentation: "expanded", appearance: "dark") + ["--notchium-quality-fixture"]
        app.launch()
        app.buttons["notchium.page.shelf"].click()
        app.buttons["Clipboard"].click()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("target check")
        let clear = app.buttons["Clear search"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(clear.frame.width, 24)
        XCTAssertGreaterThanOrEqual(clear.frame.height, 24)
        clear.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).click()
        XCTAssertEqual(search.value as? String, "")
    }

    func testStabilitySliderPointerInputAndPageOwnership() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(display: "builtInMock", surface: "physical",
            presentation: "expanded", appearance: "dark") + ["--notchium-stability-fixture"]
        app.launch()
        let home = app.buttons["notchium.page.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.click()
        let seek = app.sliders.matching(NSPredicate(format: "label == 'Playback position' AND enabled == true")).firstMatch
        XCTAssertTrue(seek.waitForExistence(timeout: 5))
        seek.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Play' AND enabled == true")).firstMatch.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == 'Pause' AND enabled == true")).firstMatch.exists,
                       "Seeking a paused track must preserve its playback state")
        XCTAssertTrue(home.isSelected)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH '1:'")).firstMatch.exists, app.debugDescription)
        seek.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.1, thenDragTo: seek.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertTrue(home.isSelected)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH '2:'")).firstMatch.exists, app.debugDescription)
        app.buttons["notchium.page.music"].click()
        let musicSeek = app.sliders.matching(NSPredicate(format: "label == 'Playback position' AND enabled == true")).firstMatch
        musicSeek.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH '0:'")).firstMatch.exists, app.debugDescription)
        let volume = app.sliders.matching(NSPredicate(format: "label == 'Spotify volume' AND enabled == true")).firstMatch
        let originalVolume = String(describing: volume.value)
        XCTAssertNotNil(volume.value, volume.debugDescription)
        volume.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).click()
        let clickedValue = String(describing: volume.value)
        XCTAssertNotEqual(clickedValue, originalVolume)
        volume.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
            .click(forDuration: 0.1, thenDragTo: volume.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)))
        XCTAssertNotEqual(String(describing: volume.value), clickedValue)
        XCTAssertTrue(app.buttons["notchium.page.music"].isSelected)
        app.buttons["notchium.page.audio"].click()
        let output = app.sliders.matching(NSPredicate(format: "label == 'System volume' AND enabled == true")).firstMatch
        let originalOutput = String(describing: output.value)
        XCTAssertNotNil(output.value, output.debugDescription)
        output.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).click()
        XCTAssertNotEqual(String(describing: output.value), originalOutput)
        output.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
            .click(forDuration: 0.1, thenDragTo: output.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)))
        XCTAssertTrue(app.buttons["notchium.page.audio"].isSelected)
        for page in ["calendar", "home", "music", "audio", "home"] {
            app.buttons["notchium.page.\(page)"].click()
            XCTAssertTrue(app.buttons["notchium.page.\(page)"].isSelected)
        }
    }

    func testCaffeineFivePointerClicksToggleMacAndDisplayAwake() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(display: "builtInMock", surface: "physical", presentation: "expanded", appearance: "dark")
        app.launch()
        let caffeine = shellElement("notchium.shell.caffeine", in: app)
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        for repetition in 1...5 {
            XCTAssertEqual(caffeine.value as? String, "Off")
            caffeine.click()
            XCTAssertTrue(waitForCaffeine("Keeping Mac and display awake", element: caffeine), "Click \(repetition)")
            caffeine.click()
            XCTAssertTrue(waitForCaffeine("Off", element: caffeine))
        }
    }

    func testCaffeineRightClickDurationMenuRetainsTheOpenPage() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(display: "builtInMock", surface: "physical", presentation: "expanded",
                                               appearance: "dark")
        app.launch()
        let caffeine = shellElement("notchium.shell.caffeine", in: app)
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        let home = app.buttons["notchium.page.home"]
        home.click()
        caffeine.rightClick()
        let fifteenMinutes = app.menuItems["15 minutes"]
        XCTAssertTrue(fifteenMinutes.waitForExistence(timeout: 3))
        for title in ["30 minutes", "1 hour", "2 hours"] { XCTAssertTrue(app.menuItems[title].exists) }
        fifteenMinutes.click()
        XCTAssertTrue(waitForCaffeine("Keeping Mac and display awake", element: caffeine))
        XCTAssertTrue(home.isSelected)
        caffeine.click()
        XCTAssertTrue(waitForCaffeine("Off", element: caffeine))
    }

    private func waitForCaffeine(_ value: String, element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "value == %@ OR value BEGINSWITH %@", value, value + " · "), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 2) == .completed
    }

    func testStage11ReminderFocusSaveEscapeAndRetention() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(display: "builtInMock", surface: "physical", presentation: "expanded", appearance: "dark")
        app.launch()
        let reminder = shellElement("notchium.shell.quickReminder", in: app)
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        XCTAssertFalse(shellElement("notchium.shell.keyboardLock", in: app).exists)
        reminder.click()
        let title = app.textFields["notchium.reminder.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("Call dentist")
        XCTAssertEqual(title.value as? String, "Call dentist")
        attachScreenshot(named: "stage11-reminder")
        XCTAssertTrue(waitForState("expanded", in: app, timeout: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Reminder Added"].waitForExistence(timeout: 3))
        XCTAssertFalse(title.exists)
        reminder.click()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        app.typeText("Discard this")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(title.exists)
        XCTAssertTrue(reminder.exists)
    }

    func testStage11ReminderAddMouseAndReturnUseSameValidation() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(display: "builtInMock", surface: "physical", presentation: "expanded", appearance: "light")
        app.launch()
        let reminder = shellElement("notchium.shell.quickReminder", in: app)
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        reminder.click()
        let title = app.textFields["notchium.reminder.title"]
        let add = app.buttons["notchium.reminder.add"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("friday 1pm")
        XCTAssertFalse(add.isEnabled)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.exists)
        app.typeKey("a", modifierFlags: .command)
        app.typeText("test friday 1:00pm")
        XCTAssertTrue(add.isEnabled)
        add.click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
        reminder.click()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "")
        app.typeText("call dentist tomorrow 10:30am")
        XCTAssertTrue(add.isEnabled)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
    }

    func testStage11DeniedReminderHasGuidanceWithoutSuccess() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(display: "builtInMock", surface: "physical", presentation: "expanded", appearance: "dark") + ["--notchium-reminders-denied"]
        app.launch()
        let reminder = shellElement("notchium.shell.quickReminder", in: app)
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        reminder.click()
        XCTAssertTrue(app.buttons["Open System Settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Add"].isEnabled)
        XCTAssertFalse(app.staticTexts["Reminder Added"].exists)
        attachScreenshot(named: "stage11-reminder-denied")
    }

    func testExpandedGearReopensExistingSettingsScene() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(display: "builtInMock", surface: "physical",
            presentation: "collapsed", appearance: "system") + ["--notchium-media-settings-fixture"]
        app.launch()
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 5))
        XCTAssertFalse(shellElement("notchium.shell.settings", in: app).exists)
        let runningApp = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.marcusyu.notchium")
                .max { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        )
        XCTAssertTrue(waitForActivationPolicy(.accessory, application: runningApp))

        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        for attempt in 0..<3 {
            shellElement("notchium.shell", in: app)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07)).click()
            let gear = shellElement("notchium.shell.settings", in: app)
            XCTAssertTrue(gear.waitForExistence(timeout: 5))
            gear.click()
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForActivationPolicy(.regular, application: runningApp),
                          "Settings must show Notchium in the Dock")
            XCTAssertEqual(app.windows.matching(identifier: "com_apple_SwiftUI_Settings_window").count, 1)
            let mediaCategory = settings.buttons["notchium.settings.category.media"]
            XCTAssertTrue(mediaCategory.waitForExistence(timeout: 5), settings.debugDescription)
            // Click the actual row bounds; macOS 27's automatic List scrolling can target
            // the identity-binding scroll container instead of this visible link.
            mediaCategory.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            XCTAssertTrue(settings.descendants(matching: .any)["notchium.settings.spotifyClientID"]
                .waitForExistence(timeout: 5), settings.debugDescription)
            // The second click restores the minimized window; the third reopens it.
            if attempt == 0 {
                settings.buttons[XCUIIdentifierMinimizeWindow].click()
                XCTAssertTrue(waitForActivationPolicy(.regular, application: runningApp),
                              "Minimized Settings must keep Notchium in the Dock")
            } else {
                settings.buttons[XCUIIdentifierCloseWindow].click()
                XCTAssertTrue(waitForActivationPolicy(.accessory, application: runningApp),
                              "Closing Settings must return to menu-bar mode")
            }
            XCTAssertTrue(waitForState("collapsed", in: app, timeout: 5))
        }
    }

    override nonisolated func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testApplicationRemainsRunningWithoutTraditionalWindows() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(app, display: "builtInMock", surface: "physical")

        XCTAssertTrue(shellElement("notchium.shell", in: app).waitForExistence(timeout: 5))

        let idle = expectation(description: "App remains alive while idle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            idle.fulfill()
        }
        wait(for: [idle], timeout: 4)

        XCTAssertNotEqual(app.state, .notRunning)
    }

    func testPhysicalShellHoverExpandCloseAndRelaunchWithoutPermissionPrompts() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(app, display: "builtInMock", surface: "physical")

        XCTAssertTrue(shellElement("notchium.shell", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 2))
        let collapsedShell = shellElement("notchium.shell", in: app)
        XCTAssertEqual(collapsedShell.frame.width, 740, accuracy: 1)
        XCTAssertEqual(collapsedShell.frame.height, 322, accuracy: 1)
        XCTAssertFalse(app.staticTexts["Notchium is ready"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attachScreenshot(named: "physical-collapsed")

        app.terminate()
        launch(app, display: "builtInMock", surface: "physical", presentation: "hovered")
        XCTAssertTrue(waitForState("hovered", in: app, timeout: 5))
        attachScreenshot(named: "physical-hovered")

        app.terminate()
        launch(app, display: "builtInMock", surface: "physical", presentation: "expanded")
        XCTAssertTrue(waitForState("expanded", in: app, timeout: 5))
        attachScreenshot(named: "physical-expanded")

        shellElement("notchium.shell.close", in: app).click()
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 2))

        app.terminate()
        app.launchArguments = fixtureArguments(
            display: "builtInMock",
            surface: "physical",
            presentation: "collapsed",
            appearance: "system"
        )
        app.launch()
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testExpandedShellClosesWithOwnControlAndOutsideFocusLoss() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(app, display: "builtInMock", surface: "physical", presentation: "expanded")

        shellElement("notchium.shell.close", in: app).click()
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 2))

        app.terminate()
        launch(app, display: "builtInMock", surface: "physical", presentation: "expanded")
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let finderMenuBar = finder.menuBars.firstMatch
        XCTAssertTrue(finderMenuBar.waitForExistence(timeout: 2))
        finderMenuBar
            .coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.50))
            .click()
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 2))
        app.activate()
    }

    func testPhysicalShellLightAndDarkFixtures() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(
            app,
            display: "builtInMock",
            surface: "physical",
            presentation: "expanded",
            appearance: "light"
        )
        XCTAssertTrue(waitForState("expanded", in: app, timeout: 5))
        attachScreenshot(named: "physical-light-expanded")

        app.terminate()
        app.launchArguments = fixtureArguments(
            display: "builtInMock",
            surface: "physical",
            presentation: "expanded",
            appearance: "dark"
        )
        app.launch()
        XCTAssertTrue(waitForState("expanded", in: app, timeout: 5))
        attachScreenshot(named: "physical-dark-expanded")
    }

    func testTransparencyFallbackFixtureHasNoPermissionAlerts() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(
            app,
            display: "builtInMock",
            surface: "physical",
            presentation: "expanded",
            appearance: "system",
            reduceTransparency: "on"
        )

        XCTAssertTrue(waitForState("expanded", in: app, timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        attachScreenshot(named: "physical-reduce-transparency")
    }

    func testRepeatedTransitionsForProfiling() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(app, display: "builtInMock", surface: "physical")

        for _ in 0..<6 {
            app.terminate()
            launch(app, display: "builtInMock", surface: "physical", presentation: "expanded")
            XCTAssertTrue(waitForState("expanded", in: app, timeout: 5))
            shellElement("notchium.shell.close", in: app).click()
            XCTAssertTrue(waitForState("collapsed", in: app, timeout: 2))
        }
    }

    func testDebugGeometryOverlayUsesTheCollapsedHardwareFootprint() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = fixtureArguments(
            display: "builtInMock",
            surface: "physical",
            presentation: "collapsed",
            appearance: "system",
            showGeometry: true
        )
        app.launch()

        let shell = shellElement("notchium.shell", in: app)
        XCTAssertTrue(shell.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 2))
        // This is the transparent hosting panel, not the visible collapsed notch.
        XCTAssertEqual(shell.frame.width, 740, accuracy: 1)
        XCTAssertEqual(shell.frame.height, 322, accuracy: 1)
        attachScreenshot(named: "physical-collapsed-geometry-overlay")
    }

    private func launch(
        _ app: XCUIApplication,
        display: String,
        surface: String,
        presentation: String = "collapsed",
        appearance: String = "system",
        reduceTransparency: String = "system"
    ) {
        app.launchArguments = fixtureArguments(
            display: display,
            surface: surface,
            presentation: presentation,
            appearance: appearance,
            reduceTransparency: reduceTransparency
        )
        app.launch()
    }

    private func fixtureArguments(
        display: String,
        surface: String,
        presentation: String,
        appearance: String,
        reduceTransparency: String = "system",
        showGeometry: Bool = false
    ) -> [String] {
        [
            "--ui-testing",
            // Display fixtures alone still start production services and access Keychain.
            "--notchium-stage11-fixture",
            "--notchium-display", display,
            "--notchium-surface", surface,
            "--notchium-presentation", presentation,
            "--notchium-appearance", appearance,
            "--notchium-reduce-motion", "on",
            "--notchium-reduce-transparency", reduceTransparency,
            "--notchium-show-geometry", showGeometry ? "on" : "off",
        ]
    }

    private func shellElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForState(
        _ state: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        shellElement("notchium.shell.state.\(state)", in: app)
            .waitForExistence(timeout: timeout)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForActivationPolicy(
        _ policy: NSApplication.ActivationPolicy,
        application: NSRunningApplication
    ) -> Bool {
        let predicate = NSPredicate(format: "activationPolicy == %d", policy.rawValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: application)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

}
