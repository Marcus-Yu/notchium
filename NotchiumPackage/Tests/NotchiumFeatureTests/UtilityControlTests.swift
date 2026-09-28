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
