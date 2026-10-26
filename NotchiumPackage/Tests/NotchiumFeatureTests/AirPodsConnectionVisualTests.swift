import AppKit
import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

/// Opt-in native-host captures using only synthetic audio events. Set
/// NOTCHIUM_AIRPODS_CAPTURE_DIR to inspect the real shell and its product turn frame by frame.
@MainActor
final class AirPodsConnectionVisualTests: XCTestCase {
    func testCaptureConnectionReconnectReducedMotionAndExit() async throws {
        guard let directory = ProcessInfo.processInfo.environment["NOTCHIUM_AIRPODS_CAPTURE_DIR"] else {
            throw XCTSkip("Set NOTCHIUM_AIRPODS_CAPTURE_DIR for animation captures")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let clock = TestAppClock(now: .now, automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(clock: clock)
        let layout = NotchGeometryResolver.layout(for:
            .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        let host = NSHostingView(rootView: NotchiumShellView(model: model, layout: layout,
            renderConfiguration: .init(appearance: .dark, reduceMotion: .off))
            .frame(width: layout.panelFrame.width, height: layout.panelFrame.height))
        host.frame = CGRect(origin: .zero, size: layout.panelFrame.size)
        host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: layout.panelFrame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(white: 0.35, alpha: 1)
        window.contentView = host
        window.orderBack(nil)
        defer { window.close(); model.activityCoordinator.clearAll() }

        func capture(_ name: String) throws -> Data {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("\(name).png"))
            return png
        }

        func frames(_ name: String, count: Int, interval: Duration = .milliseconds(40)) async throws {
            let start = ContinuousClock.now
            for index in 0..<count {
                _ = try capture(String(format: "%@-%02d", name, index))
                try await Task.sleep(until: start + interval * (index + 1), clock: .continuous)
            }
        }

        func event(connected: Bool, style: NotchDeviceStyle = .airPodsPro,
                   deviceID: String = "visual-pods", revision: UInt64 = 0) -> NotchNotification {
            .audio(.init(kind: connected ? .outputChanged : .deviceDisconnected,
                deviceName: "AirPods Pro", volume: 0.5, isMuted: false, deviceStyle: style,
                deviceID: deviceID, battery: connected ? .init(level: 0.82, isCharging: false) : nil,
                transitionRevision: revision))
        }

        func glyphColumns(connected: Bool, pixelsWide: Int) throws -> Range<Int> {
            let activity = try XCTUnwrap(event(connected: connected).content.compactActivity)
            let geometry = NotchCompactGeometry(layout: layout, activity: activity)
            let scale = CGFloat(pixelsWide) / layout.panelFrame.width
            let center = layout.collapsedVisibleFrame.midX - layout.panelFrame.minX
            let start = Int((center - geometry.bodyWidth / 2 + 13) * scale)
            return start..<(start + Int(28 * scale))
        }

        func assertDisconnectTurns(_ prefix: String, connected: Bool = false) throws {
            let first = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf:
                output.appendingPathComponent("\(prefix)-14.png"))))
            let second = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf:
                output.appendingPathComponent("\(prefix)-22.png"))))
            let activity = try XCTUnwrap(event(connected: connected).content.compactActivity)
            let geometry = NotchCompactGeometry(layout: layout, activity: activity)
            let scale = CGFloat(first.pixelsWide) / layout.panelFrame.width
            let columns = try glyphColumns(connected: connected, pixelsWide: first.pixelsWide)
            var changed = 0
            // After the shell settles, only the product may change in this 28pt leading slot.
            for y in 0..<Int(geometry.height * scale) {
                for x in columns {
                    let a = try XCTUnwrap(first.colorAt(x: x, y: y))
                    let b = try XCTUnwrap(second.colorAt(x: x, y: y))
                    if abs(a.redComponent - b.redComponent) > 0.05 { changed += 1 }
                }
            }
            XCTAssertGreaterThan(changed, 20, "A confirmed device transition must visibly turn the product")
        }

        try await Task.sleep(for: .milliseconds(100))
        _ = try capture("00-rest")
        model.notificationCoordinator.present(event(connected: true))
        try await frames("01-connect", count: 34)
        _ = try capture("02-settled")

        // Same artwork/name/connected state and same coalesced banner: switching the route
        // to another pair, or explicitly selecting the newly available pair, must turn again.
        model.showAudioHUD(.init(kind: .outputChanged, deviceName: "AirPods Pro", volume: 0.5,
            isMuted: false, deviceStyle: .airPodsPro, deviceID: "other-pods",
            battery: .init(level: 0.82, isCharging: false)))
        try await frames("02b-manual-other-pair", count: 34)
        try assertDisconnectTurns("02b-manual-other-pair", connected: true)
        model.showAudioHUD(.init(kind: .outputChanged, deviceName: "AirPods Pro", volume: 0.5,
            isMuted: false, deviceStyle: .airPodsPro, deviceID: "other-pods",
            battery: .init(level: 0.82, isCharging: false), transitionRevision: 1))
        try await frames("02c-manual-same-pair", count: 34)
        try assertDisconnectTurns("02c-manual-same-pair", connected: true)

        // The same coalesced activity turns back on disconnect and forward on reconnect.
        model.notificationCoordinator.present(event(connected: false))
        try await frames("03-disconnect", count: 34)
        try assertDisconnectTurns("03-disconnect")
        model.notificationCoordinator.present(event(connected: true))
        try await frames("04-reconnect", count: 9)
        model.notificationCoordinator.present(event(connected: false))
        try await frames("04b-reverse-during-turn", count: 6)
        model.notificationCoordinator.present(event(connected: true))
        try await frames("04c-reconnect-during-turn", count: 6)
        model.setReduceMotion(true)
        try await Task.sleep(for: .milliseconds(150))
        let reduced = try capture("05-reduced")
        model.setReduceMotion(false)
        try await Task.sleep(for: .milliseconds(150))
        let resumed = try capture("06-motion-restored")
        let reducedBitmap = try XCTUnwrap(NSBitmapImageRep(data: reduced))
        let resumedBitmap = try XCTUnwrap(NSBitmapImageRep(data: resumed))
        // Check the product itself: shell-mask alpha and the tiny charge arc can still settle
        // independently. Neither is evidence that the product turn replayed.
        let columns = try glyphColumns(connected: true, pixelsWide: reducedBitmap.pixelsWide)
        for y in 0..<80 {
            for x in columns {
                let first = try XCTUnwrap(reducedBitmap.colorAt(x: x, y: y))
                let last = try XCTUnwrap(resumedBitmap.colorAt(x: x, y: y))
                XCTAssertEqual(first.redComponent, last.redComponent, accuracy: 0.01)
                XCTAssertEqual(first.greenComponent, last.greenComponent, accuracy: 0.01)
                XCTAssertEqual(first.blueComponent, last.blueComponent, accuracy: 0.01)
            }
        }

        model.notificationCoordinator.dismissByUser()
        try await frames("07-exit", count: 12)
        _ = try capture("08-restored")

        model.notificationCoordinator.present(event(connected: false))
        try await frames("08b-fresh-disconnect", count: 34)
        try assertDisconnectTurns("08b-fresh-disconnect")
        model.notificationCoordinator.dismissByUser()
        try await Task.sleep(for: .milliseconds(500))

        for style in [NotchDeviceStyle.airPods, .airPodsMax] {
            model.notificationCoordinator.present(event(connected: true, style: style))
            try await frames("09-\(style.rawValue)", count: 34)
            model.notificationCoordinator.dismissByUser()
            try await Task.sleep(for: .milliseconds(500))
        }
    }
}
