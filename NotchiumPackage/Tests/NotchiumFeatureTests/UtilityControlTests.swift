import AppKit
import Foundation
import NotchiumCaffeineFeature
import NotchiumCore
@testable import NotchiumDynamicIsland
@testable import NotchiumServices
import CoreGraphics
import XCTest

@MainActor
final class UtilityControlTests: XCTestCase {
    func testCaffeineClicksToggleMacAndDisplayAwake() async {
        let service = MockCaffeineService()
        let model = CaffeineControlModel(service: service)
        model.start()
        defer { model.stop() }
        await drainMainActorTasks()

        model.cycleMode()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .systemAndDisplay)

        model.cycleMode()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .off)

        model.keepDisplayAwake()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .systemAndDisplay)

        model.cycleMode()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .off)
    }

    func testCaffeineHoldFromGreenAndBlueClick() async {
        let model = CaffeineControlModel(service: MockCaffeineService())
        model.start()
        defer { model.stop() }
        await drainMainActorTasks()
        model.cycleMode()
        await drainMainActorTasks()
        model.keepDisplayAwake()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .systemAndDisplay)
        model.cycleMode()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .off)
    }

    func testCaffeinePressDeadlineConsumesClickExactlyOnce() {
        let start = ContinuousClock.now
        var press = CaffeinePressState()
        press.begin(at: start)
        XCTAssertFalse(press.complete(at: start + .milliseconds(749)))
        XCTAssertTrue(press.complete(at: start + .milliseconds(750)))
        XCTAssertFalse(press.complete(at: start + .seconds(1)))
        XCTAssertFalse(press.end())
        XCTAssertFalse(press.end())
    }

    func testCaffeineShortPressClicksAndCancelledPressDoesNothing() {
        let start = ContinuousClock.now
        var press = CaffeinePressState()
        press.begin(at: start)
        XCTAssertFalse(press.complete(at: start + .milliseconds(200)))
        XCTAssertTrue(press.end())
        XCTAssertFalse(press.complete(at: start + .seconds(1)))
        press.begin(at: start)
        press.cancel()
        XCTAssertFalse(press.complete(at: start + .seconds(1)))
        XCTAssertFalse(press.end())
    }

    /// XPC delivers proxy errors and connection invalidation on its own queue. Those callbacks
    /// must not inherit the controller's main-actor isolation (Swift 6 traps on entry).
    func testLidHelperRemovalCallbacksToleratePrivateXPCQueue() async throws {
        let controller = LidAwakeController()
        await controller.removeHelper()
        try await Task.sleep(for: .seconds(1))
        await drainMainActorTasks()
        XCTAssertFalse(controller.isEnabled)
    }

}

@MainActor
final class CaffeinePressInteractionTests: XCTestCase {
    func testClickOnlyPressFeedbackBeginsBeforeActionAndClearsOnCancellation() {
        let press = CaffeinePressInteraction()
        var clicks = 0
        var holds = 0
        press.begin(allowsHold: false, click: { clicks += 1 }, hold: { holds += 1 })
        XCTAssertTrue(press.isPressed)
        XCTAssertEqual(clicks, 0)
        XCTAssertEqual(press.progress, 0)
        press.end()
        XCTAssertFalse(press.isPressed)
        XCTAssertEqual(clicks, 1)
        XCTAssertEqual(holds, 0)

        press.begin(allowsHold: false, click: { clicks += 1 }, hold: { holds += 1 })
        press.cancel()
        press.end()
        XCTAssertFalse(press.isPressed)
        XCTAssertEqual(clicks, 1)
    }

    func testNativeDisableCancelsPressAndSuppressesHoverAndClick() {
        let press = CaffeinePressInteraction()
        let view = CaffeinePointerInput.PressView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        var clicks = 0
        var hoverEvents: [Bool] = []
        func input(enabled: Bool) -> CaffeinePointerInput {
            .init(interaction: press, isEnabled: enabled, allowsHold: false,
                  click: { clicks += 1 }, hold: {}, hoverAction: { hoverEvents.append($0) })
        }
        view.updateInput(input(enabled: true))
        view.mouseEntered(with: mouse(.leftMouseDown, x: 14))
        view.mouseDown(with: mouse(.leftMouseDown, x: 14))
        XCTAssertEqual(hoverEvents, [true])
        XCTAssertTrue(press.isPressed)
        view.updateInput(input(enabled: false))
        view.mouseEntered(with: mouse(.leftMouseDown, x: 14))
        view.mouseUp(with: mouse(.leftMouseUp, x: 14))
        XCTAssertEqual(hoverEvents, [true], "Disabled native input must not request hover feedback")
        XCTAssertFalse(press.isPressed)
        XCTAssertEqual(clicks, 0)
    }

    func testProgressAndReleaseShareDeadline() {
        let press = CaffeinePressInteraction()
        let start = ContinuousClock.now
        var clicks = 0
        var holds = 0
        press.begin(allowsHold: true, click: { clicks += 1 }, hold: { holds += 1 }, at: start)
        press.advance(to: start + .milliseconds(375))
        XCTAssertEqual(press.progress, 0.5, accuracy: 0.001)
        press.end(at: start + .milliseconds(400))
        XCTAssertEqual(clicks, 1)
        XCTAssertEqual(holds, 0)
        XCTAssertEqual(press.progress, 0)
        press.advance(to: start + .seconds(1))
        XCTAssertEqual(holds, 0)

        press.begin(allowsHold: true, click: { clicks += 1 }, hold: { holds += 1 }, at: start)
        press.end(at: start + .milliseconds(750))
        press.end(at: start + .seconds(1))
        XCTAssertEqual(holds, 1)
        XCTAssertEqual(clicks, 1)
    }

    func testCancelledPressCannotRestartOrFireLater() {
        let press = CaffeinePressInteraction()
        let start = ContinuousClock.now
        var actions = 0
        press.begin(allowsHold: true, click: { actions += 1 }, hold: { actions += 1 }, at: start)
        press.cancel()
        press.advance(to: start + .seconds(1))
        press.end(at: start + .seconds(1))
        XCTAssertEqual(actions, 0)
    }

    func testBlueHoldOnlyPerformsClickOnRelease() {
        let press = CaffeinePressInteraction()
        let start = ContinuousClock.now
        var clicks = 0
        var holds = 0
        press.begin(allowsHold: false, click: { clicks += 1 }, hold: { holds += 1 }, at: start)
        press.end(at: start + .seconds(1))
        XCTAssertEqual(clicks, 1)
        XCTAssertEqual(holds, 0)
    }

    func testTwentyNativePressSequencesReachBlueDespiteMovementAndViewUpdates() async throws {
        let model = CaffeineControlModel(service: MockCaffeineService())
        defer { model.stop() }
        let view = CaffeinePointerInput.PressView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        for repetition in 1...20 {
            XCTAssertEqual(model.mode, .off)
            view.input = .init(interaction: model.pressInteraction, isEnabled: true, allowsHold: true,
                               click: model.cycleMode, hold: model.keepDisplayAwake)
            view.mouseDown(with: mouse(.leftMouseDown, x: 14))
            view.mouseDragged(with: mouse(.leftMouseDragged, x: 30))
            // Simulate a SwiftUI reconciliation while a native mouse sequence is active.
            view.input = .init(interaction: model.pressInteraction, isEnabled: true, allowsHold: true,
                               click: model.cycleMode, hold: model.keepDisplayAwake)
            try await Task.sleep(for: .milliseconds(800))
            XCTAssertEqual(model.mode, .systemAndDisplay, "Hold \(repetition) must fire before release")
            XCTAssertEqual(model.pressInteraction.progress, 1)
            view.input = .init(interaction: model.pressInteraction, isEnabled: false, allowsHold: false,
                               click: model.cycleMode, hold: model.keepDisplayAwake)
            view.mouseUp(with: mouse(.leftMouseUp, x: 30))
            await drainMainActorTasks()
            XCTAssertEqual(model.mode, .systemAndDisplay, "Release must not also click")
            XCTAssertEqual(model.pressInteraction.completionCount, repetition)
            model.cycleMode()
            await drainMainActorTasks()
        }
    }

    private func mouse(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 14), modifierFlags: [],
                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
}
