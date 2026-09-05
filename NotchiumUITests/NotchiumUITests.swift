import XCTest

@MainActor
final class NotchiumUITests: XCTestCase {
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
        XCTAssertEqual(collapsedShell.frame.width, 640, accuracy: 1)
        XCTAssertEqual(collapsedShell.frame.height, 210, accuracy: 1)
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
        XCTAssertEqual(shell.frame.width, 640, accuracy: 1)
        XCTAssertEqual(shell.frame.height, 210, accuracy: 1)
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

}
