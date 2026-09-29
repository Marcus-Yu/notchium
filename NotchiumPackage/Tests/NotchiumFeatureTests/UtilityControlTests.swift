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
    func testCaffeineClicksToggleAndHoldSelectsDisplayMode() async {
        let service = MockCaffeineService()
        let model = CaffeineControlModel(service: service)
        model.start()
        defer { model.stop() }
        await drainMainActorTasks()

        model.cycleMode()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .system)

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

}

@MainActor
final class CaffeinePressInteractionTests: XCTestCase {
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
