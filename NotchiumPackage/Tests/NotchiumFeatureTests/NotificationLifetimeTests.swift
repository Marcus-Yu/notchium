import AppKit
import Foundation
import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class NotificationLifetimeTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func drain() async { for _ in 0..<200 { await Task.yield() } }
    private func reminder() -> NotchNotification {
        .init(kind: .reminder5, coalescingKey: "event", action: .calendar,
              presentationStyle: .calendar, content: .calendar(title: "Meeting", status: "5 min"))
    }

    func testExpiryWhileOpenNeverReturnsAfterCollapse() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(clock: clock)
        model.notificationCoordinator.present(reminder())
        await clock.waitForPendingSleeps()
        let deadline = model.notificationCoordinator.expiresAt
        await clock.advance(by: .seconds(1))
        model.setHovered(true)
        await drain()
        await clock.advance(by: .milliseconds(120))
        await drain()
        XCTAssertEqual(model.visualState, .hovered)
        XCTAssertEqual(model.notificationCoordinator.expiresAt, deadline)
        XCTAssertNil(model.presentedNotification)
        await clock.advance(by: .seconds(4))
        await drain()
        XCTAssertNil(model.notificationCoordinator.active)
        model.collapse()
        XCTAssertEqual(model.surfaceState, .collapsed)
        XCTAssertNil(model.activityCoordinator.activeTransient)
        model.reset()
    }

    func testCollapseBeforeExpiryKeepsOnlyRemainingTime() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(clock: clock)
        model.notificationCoordinator.present(reminder())
        await clock.waitForPendingSleeps()
        let deadline = model.notificationCoordinator.expiresAt
        await clock.advance(by: .seconds(1))
        model.setExpanded(true)
        await drain()
        await clock.advance(by: .seconds(2))
        await drain()
        model.collapse()
        XCTAssertNotNil(model.presentedNotification)
        XCTAssertEqual(model.notificationCoordinator.expiresAt, deadline)
        await drain()
        await clock.advance(by: .milliseconds(1990))
        await drain()
        XCTAssertNotNil(model.notificationCoordinator.active)
        await clock.advance(by: .milliseconds(10))
        await drain()
        XCTAssertNil(model.notificationCoordinator.active)
        model.reset()
    }

    func testOutputExpiresAtTwoAndAHalfSecondsEvenWhenHovered() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(clock: clock)
        model.showAudioHUD(.init(kind: .outputChanged, deviceName: "AirPods", volume: 0.4, isMuted: false))
        await clock.waitForPendingSleeps()
        model.notificationCoordinator.setHovered(true)
        await clock.advance(by: .milliseconds(2490))
        await drain()
        XCTAssertNotNil(model.notificationCoordinator.active)
        await clock.advance(by: .milliseconds(10))
        await drain()
        XCTAssertNil(model.notificationCoordinator.active)
        model.reset()
    }

    func testPanelActivationAreaWinsOverCalendarAndAudioBanner() async {
        for notification in [reminder(), .audio(.init(kind: .volume, deviceName: "Speakers", volume: 0.4, isMuted: false))] {
            let clock = TestAppClock(now: base, automaticallyAdvances: false)
            let model = DynamicIslandPresentationModel(clock: clock)
            let controller = NotchiumPanelController(model: model)
            defer { controller.hide(); model.reset() }
            let placement = NotchShellPlacement(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch)
            let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)
            model.notificationCoordinator.present(notification)
            controller.reconcile(placement: placement, layout: layout, renderConfiguration: .automatic, animated: false)
            let point = CGPoint(x: layout.collapsedHoverFrame.midX, y: layout.collapsedHoverFrame.midY)
            controller.handleMouseMoved(at: point)
            await drain()
            await clock.advance(by: .milliseconds(120))
            await drain()
            XCTAssertEqual(model.visualState, .hovered)
            XCTAssertNotNil(model.notificationCoordinator.active)
            model.present(.collapsed, animated: false)
            controller.handleClick(at: point)
            XCTAssertEqual(model.visualState, .expanded)
        }
    }

    func testRenderIconHeaderForEachSelectedPage() throws {
        let model = NotchPageModel()
        for page in NotchPage.allCases {
            model.selectedPage = page
            let view = NotchPagesView(model: model, mediaRenderer: nil, calendarRenderer: nil,
                                     audioRenderer: nil, isExpanded: true,
                                     caffeine: HeaderCaffeine())
                .frame(width: 524, height: 234).foregroundStyle(.white).background(.black)
                .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame = CGRect(x: 0, y: 0, width: 524, height: 234)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/tmp/notch-refined-\(page.rawValue).png"))
            XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, 524)
        }
    }
}

@MainActor private final class HeaderCaffeine: NotchCaffeineControlling {
    let pressInteraction = CaffeinePressInteraction()
    var mode: CaffeineMode { .off }
    var isBusy: Bool { false }
    func cycleMode() {}
    func keepDisplayAwake() {}
}

