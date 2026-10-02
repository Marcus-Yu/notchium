import AppKit
import NotchiumCaffeineFeature
import NotchiumCore
import NotchiumServices
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class CaffeineTimedControlTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testEveryDurationKeepsMacAndDisplayAwakeUntilExactExpiry() async {
        for duration in CaffeineDuration.allCases {
            let clock = TestAppClock(now: start, automaticallyAdvances: false)
            let model = CaffeineControlModel(service: MockCaffeineService(), clock: clock)
            defer { model.stop() }
            model.keepAwake(for: duration)
            await clock.waitForPendingSleeps()
            XCTAssertEqual(model.mode, .systemAndDisplay)
            XCTAssertEqual(model.selectedDuration, duration)
            XCTAssertEqual(model.expiresAt, start.addingTimeInterval(Double(duration.rawValue * 60)))
            await clock.advance(by: duration.duration - .seconds(1))
            await drainMainActorTasks()
            XCTAssertEqual(model.mode, .systemAndDisplay)
            await clock.advance(by: .seconds(1))
            await settle(model)
            XCTAssertEqual(model.mode, .off)
            XCTAssertNil(model.selectedDuration)
            XCTAssertNil(model.expiresAt)
        }
    }

    func testClickDisablesTimedSessionAndNextClickIsIndefinite() async {
        let clock = TestAppClock(now: start, automaticallyAdvances: false)
        let model = CaffeineControlModel(service: MockCaffeineService(), clock: clock)
        defer { model.stop() }
        model.keepAwake(for: .fifteenMinutes)
        await clock.waitForPendingSleeps()
        model.cycleMode()
        await settle(model)
        XCTAssertEqual(model.mode, .off)
        model.cycleMode()
        await settle(model)
        XCTAssertEqual(model.mode, .systemAndDisplay)
        XCTAssertNil(model.expiresAt)
        await clock.advance(by: .seconds(3 * 60 * 60))
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .systemAndDisplay, "A cancelled deadline cannot turn off a new indefinite session")
    }

    func testSelectingAnotherDurationRefreshesTheSameSessionDeadline() async {
        let clock = TestAppClock(now: start, automaticallyAdvances: false)
        let model = CaffeineControlModel(service: MockCaffeineService(), clock: clock)
        model.start()
        defer { model.stop() }
        await drainMainActorTasks()
        model.keepAwake(for: .fifteenMinutes)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(5 * 60))
        model.keepAwake(for: .thirtyMinutes)
        await settle(model)
        await clock.waitForPendingSleeps()
        XCTAssertEqual(model.expiresAt, start.addingTimeInterval(35 * 60))
        await clock.advance(by: .seconds(10 * 60))
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .systemAndDisplay, "The old 15-minute deadline no longer owns the session")
        await clock.advance(by: .seconds(20 * 60))
        await settle(model)
        XCTAssertEqual(model.mode, .off)
    }

    func testStopCancelsExpiryAndDoesNotRegisterAHelperForFixtures() async {
        let clock = TestAppClock(now: start, automaticallyAdvances: false)
        let model = CaffeineControlModel(service: MockCaffeineService(), clock: clock)
        model.keepAwake(for: .twoHours)
        await clock.waitForPendingSleeps()
        model.stop()
        XCTAssertEqual(model.mode, .off)
        XCTAssertNil(model.expiresAt)
        XCTAssertFalse(model.lidAwake.isEnabled)
        XCTAssertFalse(model.needsClosedLidApproval)
        await clock.advance(by: .seconds(2 * 60 * 60))
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .off)
    }

    func testNativeDurationMenuHasFourChoicesAndDoesNotToggleOnSelection() throws {
        let view = CaffeinePointerInput.PressView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        var clicks = 0
        var selection: CaffeineDuration?
        view.input = .init(interaction: CaffeinePressInteraction(), isEnabled: true, allowsHold: false,
                           click: { clicks += 1 }, hold: {}, selectedDuration: .thirtyMinutes,
                           durationAction: { selection = $0 })
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .init(x: 14, y: 14),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(view.menu(for: event))
        XCTAssertEqual(menu.items.map(\.title), ["15 minutes", "30 minutes", "1 hour", "2 hours"])
        XCTAssertEqual(menu.items.map(\.state), [.off, .on, .off, .off])
        for (index, duration) in CaffeineDuration.allCases.enumerated() {
            let item = menu.items[index]
            XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
            XCTAssertEqual(selection, duration)
            XCTAssertEqual(clicks, 0)
        }
    }

    private func settle(_ model: CaffeineControlModel) async {
        // Drain actor hops and fake-clock completion without waiting in real time.
        for _ in 0..<200 { await Task.yield() }
        XCTAssertFalse(model.isBusy)
    }
}
