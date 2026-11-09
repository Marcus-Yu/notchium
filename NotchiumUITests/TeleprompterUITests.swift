import AppKit
import XCTest

/// Uses the isolated, mock-backed fixture app; never opens the user's microphone or library.
@MainActor
final class TeleprompterUITests: XCTestCase {
    func testVoiceInputAndReadingSurviveClickingMeetingControlsOutsideTheNotch() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--notchium-stage11-fixture", "--notchium-teleprompter-editor-fixture",
            "--notchium-teleprompter-voice-fixture", "--notchium-display", "builtInMock",
            "--notchium-surface", "physical", "--notchium-presentation", "collapsed", "--notchium-reduce-motion", "off"]
        app.launch()
        let editor = app.windows["Teleprompter Scripts"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let open = editor.buttons["notchium.teleprompter.openReader"]
        XCTAssertTrue(waitUntilEnabled(open))
        open.click()
        let panel = app.dialogs["notchium.shell.panel"]
        let play = app.buttons["notchium.teleprompter.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        clickVisible(play, anchor: panel)
        let input = app.descendants(matching: .any)["notchium.teleprompter.inputLevel"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(play.label, "Pause teleprompter")

        let larger = app.buttons["notchium.teleprompter.font.increase"]
        let smaller = app.buttons["notchium.teleprompter.font.decrease"]
        let textSize = app.staticTexts["notchium.teleprompter.font.value"]
        XCTAssertTrue(larger.isHittable)
        XCTAssertTrue(smaller.isHittable)
        XCTAssertEqual(textSize.value as? String, "24 points")
        clickVisible(larger, anchor: panel)
        clickVisible(larger, anchor: panel)
        XCTAssertEqual(textSize.value as? String, "26 points")
        clickVisible(smaller, anchor: panel)
        XCTAssertEqual(textSize.value as? String, "25 points")
        XCTAssertEqual(play.label, "Pause teleprompter", "Changing text size must preserve active reading")
        let viewport = app.descendants(matching: .any)["notchium.teleprompter.reader"].firstMatch
        let activeLine = app.buttons["notchium.teleprompter.activeLine"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 3))
        XCTAssertTrue(activeLine.waitForExistence(timeout: 3))
        let lineOffset = activeLine.frame.minY - viewport.frame.minY
        XCTAssertGreaterThanOrEqual(lineOffset, 25, "Keep one line of context above the active line")
        XCTAssertLessThanOrEqual(lineOffset, 45, "The active line belongs near the top, not at the bottom")
        let readerPage = app.descendants(matching: .any)["notchium.teleprompter.page"].firstMatch
        // Accessibility exposes the content inside the page's two 30pt insets.
        XCTAssertGreaterThanOrEqual(readerPage.frame.width, 590, "The teleprompter uses the larger page width")
        let attachment = XCTAttachment(screenshot: panel.screenshot())
        attachment.name = "teleprompter-larger-reader-live-font-controls"
        attachment.lifetime = .keepAlways
        add(attachment)

        // A menu-bar click is outside the reader, like a click on meeting controls.
        // It must leave capture active; the second click dismisses the menu.
        let status = app.descendants(matching: .statusItem).firstMatch
        clickVisible(status, anchor: panel)
        clickVisible(status, anchor: panel)
        XCTAssertTrue(app.descendants(matching: .any)["notchium.shell.state.expanded"].exists)
        XCTAssertEqual(play.label, "Pause teleprompter")
        clickVisible(play, anchor: panel)
        XCTAssertEqual(play.label, "Start teleprompter")
    }

    func testLongScriptSaveStaysReachableAtMinimumWindowSize() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--notchium-stage11-fixture", "--notchium-teleprompter-editor-fixture",
            "--notchium-teleprompter-minimum-editor-fixture",
            "--notchium-display", "builtInMock", "--notchium-surface", "physical",
            "--notchium-presentation", "collapsed", "--notchium-reduce-motion", "on",
            "-AppleInterfaceStyle", "Light"]
        app.launch()
        let editor = app.windows["Teleprompter Scripts"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(editor.frame.width, 810)
        XCTAssertLessThanOrEqual(editor.frame.height, 590)

        let title = editor.textFields["notchium.teleprompter.title"]
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Long declaration fixture")
        let text = editor.textViews["notchium.teleprompter.text"]
        text.click()
        text.typeText(Array(repeating: "A long script keeps its document actions available while reading and editing.", count: 10)
            .joined(separator: "\n\n"))
        text.typeKey(.downArrow, modifierFlags: .command)
        text.scroll(byDeltaX: 0, deltaY: -1_000)

        let save = editor.buttons["notchium.teleprompter.save"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable, "Save must remain in the native toolbar after scrolling the script")
        XCTAssertLessThan(save.frame.maxY, text.frame.minY)
        let attachment = XCTAttachment(screenshot: editor.screenshot())
        attachment.name = "teleprompter-save-visible-long-script-minimum-window"
        attachment.lifetime = .keepAlways
        add(attachment)
        save.click()
        XCTAssertTrue(waitUntilEnabled(editor.buttons["notchium.teleprompter.openReader"]))
    }

    func testCreateScriptReadAtFixedPaceAndPause() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--notchium-stage11-fixture", "--notchium-teleprompter-editor-fixture",
            "--notchium-display", "builtInMock", "--notchium-surface", "physical",
            "--notchium-presentation", "expanded", "--notchium-appearance", "dark",
            "--notchium-reduce-motion", "on"]
        app.launch()
        // The explicit mock fixture opens the same retained native editor used by
        // the menu/page actions, without depending on synthetic menu traversal.
        let page = app.buttons["notchium.page.teleprompter"]
        let panel = app.dialogs["notchium.shell.panel"]
        let editor = app.windows["Teleprompter Scripts"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), app.debugDescription)
        let title = editor.textFields["notchium.teleprompter.title"]
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Quarterly update")
        let text = editor.textViews["notchium.teleprompter.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        text.click()
        text.typeText("Welcome everyone to our quarterly update. We shipped a simpler experience and listened carefully to your feedback. Today we will review the results and discuss our next steps together.")
        let save = editor.buttons["notchium.teleprompter.save"]
        XCTAssertTrue(save.isEnabled)
        save.click()
        let open = editor.buttons["Open Reader"]
        XCTAssertTrue(waitUntilEnabled(open), app.debugDescription)
        open.click()
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        let mode = app.popUpButtons["notchium.teleprompter.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 3), app.debugDescription)
        mode.click()
        app.menuItems["Fixed Speed"].click()
        let play = app.buttons["notchium.teleprompter.play"]
        clickVisible(play, anchor: panel)
        XCTAssertTrue(app.staticTexts["Fixed pace · microphone off"].waitForExistence(timeout: 3), app.debugDescription)
        clickVisible(play, anchor: panel)
        XCTAssertTrue(app.staticTexts["Paused · microphone off"].waitForExistence(timeout: 3), app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "teleprompter-fixed-pace-paused"
        attachment.lifetime = .keepAlways
        add(attachment)
        clickVisible(app.buttons["notchium.teleprompter.edit"], anchor: panel)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.textFields["notchium.teleprompter.title"].stringValue, "Quarterly update")
    }

    private func waitUntilEnabled(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func clickVisible(_ element: XCUIElement, anchor: XCUIElement) {
        let frame = element.frame
        let origin = anchor.frame.origin
        anchor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - origin.x, dy: frame.midY - origin.y)).click()
    }
}

private extension XCUIElement {
    var stringValue: String { value as? String ?? "" }
}
