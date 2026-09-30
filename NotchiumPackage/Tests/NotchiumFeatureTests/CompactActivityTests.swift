import Foundation
import NotchiumCore
@testable import NotchiumDynamicIsland
@testable import NotchiumFeature
import NotchiumServices
import SwiftUI
import XCTest

@MainActor
final class CompactActivityTests: XCTestCase {
    private func volume(_ level: Double) -> NotchAudioHUD {
        .init(kind: .volume, deviceName: "Speakers", volume: level, isMuted: false)
    }

    func testRepeatedVolumeUpdatesOneCompactActivityInPlace() {
        let model = DynamicIslandPresentationModel(
            clock: TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false))
        model.showAudioHUD(volume(0.4))
        let first = try? XCTUnwrap(model.presentedNotification)
        XCTAssertEqual(first?.presentationStyle, .compact)
        for level in stride(from: 0.45, through: 0.9, by: 0.05) { model.showAudioHUD(volume(level)) }
        // Holding Volume Up never replays entry: identity (and so the shell target) is unchanged.
        XCTAssertEqual(model.presentedNotification?.id, first?.id)
        XCTAssertEqual(model.presentedNotification?.content.compactActivity?.trailing, .level(0.9))
    }

    func testLowBatteryPreemptsVolumeAndVolumeCannotInterruptIt() {
        let model = DynamicIslandPresentationModel(
            clock: TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false))
        model.showAudioHUD(volume(0.4))
        XCTAssertTrue(model.notificationCoordinator.present(.lowBattery(level: 0.1)))
        XCTAssertEqual(model.presentedNotification?.kind, .lowBattery)
        model.showAudioHUD(volume(0.5))
        XCTAssertEqual(model.presentedNotification?.kind, .lowBattery)
        XCTAssertEqual(model.activityCoordinator.activeTransient?.kind, .battery)
    }

    func testCompactGeometryStaysAtNotchHeightAndFlanksTheHardware() {
        let layout = NotchGeometryResolver.layout(
            for: .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        let geometry = NotchCompactGeometry(layout: layout)
        let frame = NotchNotificationGeometry.frame(for: .compact, layout: layout)
        XCTAssertEqual(frame.height, layout.collapsedVisibleFrame.height)
        XCTAssertEqual(frame.width, geometry.bodyWidth)
        XCTAssertEqual(geometry.bodyWidth, geometry.hardwareWidth + NotchCompactGeometry.sideWidth * 2)
        XCTAssertEqual(frame.midX, layout.collapsedVisibleFrame.midX)
    }

    func testRevealFollowsInterpolatedShellWidthOnly() {
        let passive = NotchShape(width: 200, height: 32, centerX: 300, topCornerRadius: 0, bottomCornerRadius: 8)
        func frame(width: CGFloat, span: NotchCompactSpan?) -> NotchSurfaceFrame<EmptyView> {
            NotchSurfaceFrame(shape: .init(width: width, height: 32, centerX: 300, bottomRadius: 12,
                                           passiveShape: passive),
                              phase: .collapsed, expandedHeight: 32, compactSpan: span) { _ in EmptyView() }
        }
        let span = NotchCompactSpan(base: 200, full: 420)
        XCTAssertEqual(frame(width: 200, span: span).compactReveal, 0)
        XCTAssertEqual(frame(width: 310, span: span).compactReveal, 0.5, accuracy: 0.0001)
        XCTAssertEqual(frame(width: 420, span: span).compactReveal, 1)
        XCTAssertEqual(frame(width: 440, span: span).compactReveal, 1.06, accuracy: 0.0001, "spring overshoot is bounded")
        XCTAssertEqual(frame(width: 420, span: nil).compactReveal, 0, "no compact activity, no reveal")
    }

    func testDeviceClassificationUsesNameAndTransport() {
        XCTAssertEqual(NotchDeviceStyle.classify(name: "Marcus’s AirPods Pro", transport: .bluetooth), .airPodsPro)
        XCTAssertEqual(NotchDeviceStyle.classify(name: "AirPods Max", transport: .bluetooth), .airPodsMax)
        XCTAssertEqual(NotchDeviceStyle.classify(name: "WH-1000XM5", transport: .bluetooth), .headphones)
        XCTAssertEqual(NotchDeviceStyle.classify(name: "MacBook Air Speakers", transport: .builtIn), .builtIn)
        XCTAssertEqual(NotchDeviceStyle.classify(name: "LG UltraFine", transport: .display), .display)
        XCTAssertTrue(NotchDeviceStyle.airPodsPro.spinsOnConnect)
        XCTAssertFalse(NotchDeviceStyle.display.spinsOnConnect)
    }

    func testOutputActivitiesAreGlyphLedWithoutDeviceNames() {
        func output(_ style: NotchDeviceStyle) -> NotchCompactActivity {
            .init(NotchAudioHUD(kind: .outputChanged, deviceName: "Marcus’s AirPods Pro", volume: 0.5,
                                isMuted: false, deviceStyle: style))
        }
        for style in [NotchDeviceStyle.airPodsPro, .headphones, .builtIn] {
            let activity = output(style)
            XCTAssertEqual(activity.glyph, .device(style))
            XCTAssertFalse(activity.showsTitle, "no device name beside the glyph")
            XCTAssertEqual(activity.trailing, .text("Connected"))
            XCTAssertLessThan(activity.sideWidth, NotchCompactGeometry.sideWidth)
        }
        XCTAssertEqual(output(.airPodsPro).title, "AirPods Pro", "still spoken to VoiceOver")
    }

    func testMuteKeepsTheDimmedLevel() {
        let muted = NotchCompactActivity(NotchAudioHUD(kind: .volume, deviceName: "S", volume: 0.62, isMuted: true))
        XCTAssertEqual(muted.trailing, .level(0.62))
        XCTAssertEqual(muted.tint, .muted)
    }

    func testBatteryPolicyAnnouncesPlugInAndEachLowThresholdOnce() {
        func snapshot(_ level: Double, power: Bool = false) -> BatterySnapshot {
            .init(availability: .available, chargeLevel: level, isCharging: power, isConnectedToPower: power)
        }
        var policy = BatteryActivityPolicy()
        XCTAssertNil(policy.receive(snapshot(0.15)), "the state at launch is not announced")
        XCTAssertNil(policy.receive(snapshot(0.14)))
        // Stage 13: 10% is the critical threshold; unplugging is one short event.
        XCTAssertEqual(policy.receive(snapshot(0.10)), .critical(level: 0.10))
        XCTAssertNil(policy.receive(snapshot(0.09)))
        XCTAssertEqual(policy.receive(snapshot(0.09, power: true)), .charging(level: 0.09))
        XCTAssertNil(policy.receive(snapshot(0.12, power: true)))
        XCTAssertEqual(policy.receive(snapshot(0.30)), .powerDisconnected(level: 0.30))
        XCTAssertEqual(policy.receive(snapshot(0.20)), .low(level: 0.20))
        XCTAssertNil(policy.receive(snapshot(0.19)))

        var desktop = BatteryActivityPolicy()
        XCTAssertNil(desktop.receive(.init(availability: .unavailable(.unsupportedHardware))))
        XCTAssertNil(desktop.receive(.init(availability: .unavailable(.unsupportedHardware))))
    }
}
