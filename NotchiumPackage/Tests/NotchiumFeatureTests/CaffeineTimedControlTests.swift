import AppKit
import NotchiumCaffeineFeature
import NotchiumCore
import NotchiumServices
import SwiftUI
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

    func testCountdownUsesElapsedTimeAndClampsAtSessionBoundaries() {
        let expiry = start.addingTimeInterval(30 * 60)
        let countdown = CaffeineCountdown(duration: .thirtyMinutes, expiresAt: expiry,
                                          now: start.addingTimeInterval(5 * 60))
        XCTAssertEqual(countdown.elapsedProgress, 1.0 / 6, accuracy: 0.0001)
        XCTAssertEqual(countdown.remainingSeconds, 25 * 60)
        XCTAssertEqual(countdown.remainingLabel, "25:00 remaining")
        let beforeStart = CaffeineCountdown(duration: .thirtyMinutes, expiresAt: expiry,
                                            now: start.addingTimeInterval(-1))
        XCTAssertEqual(beforeStart.elapsedProgress, 0)
        XCTAssertEqual(beforeStart.remainingSeconds, 30 * 60)
        let finished = CaffeineCountdown(duration: .thirtyMinutes, expiresAt: expiry,
                                         now: expiry.addingTimeInterval(1))
        XCTAssertEqual(finished.elapsedProgress, 1)
        XCTAssertEqual(finished.remainingLabel, "0:00 remaining")
        let fractional = CaffeineCountdown(duration: .fifteenMinutes, expiresAt: expiry,
                                           now: expiry.addingTimeInterval(-0.1))
        XCTAssertEqual(fractional.remainingLabel, "0:01 remaining", "Do not display zero before expiry")
    }

    func testActiveCupHasNoIndefiniteBorderAndTimedBorderFillsClockwise() throws {
        for scale: CGFloat in [1, 2] {
            for progress: Double? in [nil, 1.0 / 6] {
                let renderer = ImageRenderer(content:
                    CaffeineShortcutLabel(isActive: true, isHovered: false, progress: progress)
                        .background(.black))
                renderer.scale = scale
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                var upperRight = 0
                var lowerHalf = 0
                var orangeBorder = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let dx = (Double(x) + 0.5) / scale - 14
                        let dy = (Double(y) + 0.5) / scale - 14
                        guard hypot(dx, dy) >= 11,
                              let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                              color.redComponent > 0.6, color.greenComponent > 0.25,
                              color.blueComponent < 0.25 else { continue }
                        orangeBorder += 1
                        if dx > 0, dy < 0 { upperRight += 1 }
                        if dy > 0 { lowerHalf += 1 }
                    }
                }
                if progress == nil {
                    XCTAssertEqual(orangeBorder, 0, "Indefinite mode has no orange border")
                } else {
                    XCTAssertGreaterThan(upperRight, 5, "The elapsed arc starts at the top and fills clockwise")
                    XCTAssertEqual(lowerHalf, 0, "One-sixth progress stays in the upper-right quadrant")
                }
            }
        }
    }

    func testNativeHoverShowsCountdownAndToggleKeepsTheSameCupView() async throws {
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let model = CaffeineControlModel(service: MockCaffeineService(), clock: clock)
        defer { model.stop() }
        model.keepAwake(for: .thirtyMinutes)
        await clock.waitForPendingSleeps()
        func button(enabled: Bool) -> some View {
            NotchCaffeineButton(controller: model)
                .frame(width: 200, height: 90, alignment: .top).background(.black)
                .disabled(!enabled)
        }
        let host = NSHostingView(rootView: button(enabled: true))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 200, height: 90),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let input = try XCTUnwrap(pointerView(in: host))
        input.updateTrackingAreas()
        XCTAssertTrue(input.trackingAreas.contains { $0.options.contains(.mouseEnteredAndExited) })
        let initialFrame = input.convert(input.bounds, to: host)
        XCTAssertEqual(try countdownInk(in: host, name: "not-hovered"), 0)

        let entered = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        input.mouseEntered(with: entered)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(try countdownInk(in: host, name: "hovered"), 30,
                             "The native pointer event must display readable countdown text below the cup")

        host.rootView = button(enabled: false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try countdownInk(in: host, name: "disabled"), 0,
                       "Disabling while hovered must remove hover-only countdown text")
        XCTAssertTrue(pointerView(in: host) === input)
        XCTAssertEqual(input.convert(input.bounds, to: host), initialFrame)
        host.rootView = button(enabled: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try countdownInk(in: host, name: "reenabled"), 0,
                       "Re-enabling must not restore stale hover feedback")
        input.mouseEntered(with: entered)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(try countdownInk(in: host, name: "hovered-again"), 30)

        let exited = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseExited, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        input.mouseExited(with: exited)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try countdownInk(in: host, name: "exited"), 0)

        model.cycleMode()
        await settle(model)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(pointerView(in: host) === input, "Turning off changes colour without replacing the cup/input view")
        XCTAssertEqual(input.convert(input.bounds, to: host), initialFrame)
        XCTAssertEqual(try countdownInk(in: host, name: "off"), 0)
    }

    private func pointerView(in view: NSView) -> CaffeinePointerInput.PressView? {
        if let input = view as? CaffeinePointerInput.PressView { return input }
        return view.subviews.lazy.compactMap { self.pointerView(in: $0) }.first
    }

    private func countdownInk<V: View>(in host: NSHostingView<V>, name: String) throws -> Int {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        var ink = 0
        for y in Int(34 * scale)..<Int(64 * scale) {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                   min(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 { ink += 1 }
            }
        }
        if ProcessInfo.processInfo.environment["NOTCHIUM_CAFFEINE_QA"] == "1" {
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-caffeine-\(name).png"))
        }
        return ink
    }

    private func settle(_ model: CaffeineControlModel) async {
        // Drain actor hops and fake-clock completion without waiting in real time.
        for _ in 0..<200 { await Task.yield() }
        XCTAssertFalse(model.isBusy)
    }
}
