import XCTest

@MainActor
final class NotchiumUITests: XCTestCase {
    override nonisolated func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPhysicalShellHoverExpandCloseAndRelaunchWithoutPermissionPrompts() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(app, display: "builtInMock", surface: "physical")

        let toggle = shellElement("notchium.shell.toggle", in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 2))
        XCTAssertEqual(app.alerts.count, 0)
        attachScreenshot(named: "physical-collapsed")

        toggle.hover()
        XCTAssertTrue(waitForState("hovered", in: app, timeout: 2))
        attachScreenshot(named: "physical-hovered")

        shellElement("notchium.shell.toggle", in: app).click()
        XCTAssertTrue(waitForState("expanded", in: app, timeout: 2))
        attachScreenshot(named: "physical-expanded")

        shellElement("notchium.shell.close", in: app).click()
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 2))

        app.terminate()
        app.launch()
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testExpandedShellClosesWithOwnControlAndOutsideFocusLoss() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(app, display: "externalMock", surface: "virtual")

        shellElement("notchium.shell.toggle", in: app).click()
        XCTAssertTrue(waitForState("expanded", in: app, timeout: 2))

        shellElement("notchium.shell.close", in: app).click()
        XCTAssertTrue(waitForState("collapsed", in: app, timeout: 2))

        shellElement("notchium.shell.toggle", in: app).click()
        XCTAssertTrue(waitForState("expanded", in: app, timeout: 2))
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

    func testVirtualPillLightAndDarkFixtures() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(
            app,
            display: "externalMock",
            surface: "virtual",
            presentation: "expanded",
            appearance: "light"
        )
        XCTAssertTrue(waitForState("expanded", in: app, timeout: 5))
        attachScreenshot(named: "virtual-light-expanded")

        app.terminate()
        app.launchArguments = fixtureArguments(
            display: "externalMock",
            surface: "virtual",
            presentation: "expanded",
            appearance: "dark"
        )
        app.launch()
        XCTAssertTrue(waitForState("expanded", in: app, timeout: 5))
        attachScreenshot(named: "virtual-dark-expanded")
    }

    func testTransparencyFallbackFixtureHasNoPermissionAlerts() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(
            app,
            display: "externalMock",
            surface: "virtual",
            presentation: "expanded",
            appearance: "system",
            reduceTransparency: "on"
        )

        XCTAssertTrue(waitForState("expanded", in: app, timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        attachScreenshot(named: "virtual-reduce-transparency")
    }

    func testRepeatedTransitionsForProfiling() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(app, display: "externalMock", surface: "virtual")

        for _ in 0..<6 {
            shellElement("notchium.shell.toggle", in: app).click()
            XCTAssertTrue(waitForState("expanded", in: app, timeout: 2))
            shellElement("notchium.shell.close", in: app).click()
            XCTAssertTrue(waitForState("collapsed", in: app, timeout: 2))
        }
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
        reduceTransparency: String = "system"
    ) -> [String] {
        [
            "--ui-testing",
            "--notchium-display", display,
            "--notchium-surface", surface,
            "--notchium-presentation", presentation,
            "--notchium-appearance", appearance,
            "--notchium-reduce-motion", "on",
            "--notchium-reduce-transparency", reduceTransparency,
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
