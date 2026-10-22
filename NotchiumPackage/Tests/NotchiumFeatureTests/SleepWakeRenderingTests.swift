import AppKit
import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

/// Uses one mounted production shell: a static render cannot demonstrate cancellation
/// of an in-flight compact retraction across a hidden native window's lifecycle.
@MainActor
final class SleepWakeRenderingTests: XCTestCase {
    func testWakeSettlesInterruptedAirPodsRetractionWithoutRemountingPages() async throws {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 10), automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let model = DynamicIslandPresentationModel(clock: clock, activityCoordinator: activities)
        let media = SleepWakeMediaRenderer()
        model.mediaRenderer = media
        let notification = NotchNotification.audio(.init(
            kind: .deviceDisconnected, deviceName: "AirPods Pro", volume: nil, isMuted: false,
            deviceStyle: .airPodsPro, deviceID: "sleep-wake-pods"))
        model.notificationCoordinator.present(notification)
        await clock.waitForPendingSleeps()

        let layout = makeLayout()
        let size = layout.panelFrame.size
        let host = NSHostingView(rootView: NotchiumShellView(model: model, layout: layout)
            .frame(width: size.width, height: size.height)
            .background(.white))
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        window.orderBack(nil)
        defer { window.close(); activities.clearAll() }

        try await Task.sleep(for: .milliseconds(80))
        let restingWidth = layout.collapsedVisibleFrame.width
        let compactWidth = try shellWidth(in: host, height: layout.collapsedVisibleFrame.height)
        XCTAssertGreaterThan(compactWidth, restingWidth + 100,
                             "The actual AirPods disconnect row must be visible before expiry")
        XCTAssertEqual(media.probe.mountCount, 1)

        await clock.advance(by: notification.duration)
        var intermediateWidth: CGFloat?
        for _ in 0..<15 {
            try await Task.sleep(for: .milliseconds(16))
            let width = try shellWidth(in: host, height: layout.collapsedVisibleFrame.height)
            if width > restingWidth + 4, width < compactWidth - 4 {
                intermediateWidth = width
                break
            }
        }
        // Offscreen hosting does not expose live spring frames on every runner.
        // Without one, this environment cannot verify interruption cancellation.
        try XCTSkipIf(intermediateWidth == nil,
                      "Offscreen native hosting did not expose an intermediate compact retraction frame")
        XCTAssertNil(model.notificationCoordinator.active)

        // Hide the same host while its target is already resting, then apply the
        // production lifecycle revisions. The wake must discard presentation geometry,
        // retained compact content, and any completion still belonging to the old spring.
        window.orderOut(nil)
        model.prepareForSystemSleep()
        activities.setPresentationContext(.sleeping)
        model.prepareForSystemWake()
        activities.setPresentationContext(.normal)
        window.orderBack(nil)

        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(try shellWidth(in: host, height: layout.collapsedVisibleFrame.height),
                       restingWidth, accuracy: 2,
                       "The first wake frame must use resting geometry")
        XCTAssertFalse(try hasContentOutsideRestingShell(in: host, layout: layout),
                       "The expired AirPods glyph and status must not survive beside the notch")
        XCTAssertEqual(media.probe.mountCount, 1, "The existing media page must remain mounted")
        XCTAssertEqual(media.probe.dismantleCount, 0)

        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(try shellWidth(in: host, height: layout.collapsedVisibleFrame.height),
                       restingWidth, accuracy: 2,
                       "An interrupted completion must not restore the old compact geometry")
        XCTAssertFalse(try hasContentOutsideRestingShell(in: host, layout: layout))
        XCTAssertEqual(media.probe.mountCount, 1)
        XCTAssertEqual(media.probe.dismantleCount, 0)
    }

    private func makeLayout() -> NotchPanelLayout {
        let display = NotchiumDisplaySnapshot(
            id: .init(rawValue: 1), name: "Rendering fixture",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            isBuiltIn: false, isPrimary: true, statusBarThickness: 38)
        return NotchGeometryResolver.layout(
            for: .init(display: display, mode: .virtualPill), state: .collapsed)
    }

    private func snapshot(_ host: NSView) throws -> NSBitmapImageRep {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func shellWidth(in host: NSView, height: CGFloat) throws -> CGFloat {
        let bitmap = try snapshot(host)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let row = Int(height / 2 * scale)
        var first: Int?
        var last: Int?
        for x in 0..<bitmap.pixelsWide {
            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB))
            if color.redComponent < 0.1, color.greenComponent < 0.1, color.blueComponent < 0.1 {
                if first == nil { first = x }
                last = x
            }
        }
        guard let first, let last else { return 0 }
        return CGFloat(last - first + 1) / scale
    }

    private func hasContentOutsideRestingShell(in host: NSView, layout: NotchPanelLayout) throws -> Bool {
        let bitmap = try snapshot(host)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let left = (layout.collapsedVisibleFrame.minX - layout.panelFrame.minX - 2) * scale
        let right = (layout.collapsedVisibleFrame.maxX - layout.panelFrame.minX + 2) * scale
        let rows = min(bitmap.pixelsHigh, Int((layout.collapsedVisibleFrame.height + 2) * scale))
        for y in 0..<rows {
            for x in 0..<bitmap.pixelsWide where CGFloat(x) < left || CGFloat(x) > right {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if min(color.redComponent, color.greenComponent, color.blueComponent) < 0.95 { return true }
            }
        }
        return false
    }
}

@MainActor
private final class SleepWakeMediaRenderer: NotchMediaRendering {
    let probe = SleepWakePageMountProbe()
    var collapsedMediaVisible: Bool { false }

    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView { AnyView(EmptyView()) }
    func expandedMedia() -> AnyView { AnyView(SleepWakePageProbeView(probe: probe)) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(EmptyView()) }
}

@MainActor
private final class SleepWakePageMountProbe {
    var mountCount = 0
    var dismantleCount = 0
}

private struct SleepWakePageProbeView: NSViewRepresentable {
    let probe: SleepWakePageMountProbe

    func makeNSView(context: Context) -> NSView {
        probe.mountCount += 1
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> SleepWakePageMountProbe { probe }

    static func dismantleNSView(_ nsView: NSView, coordinator: SleepWakePageMountProbe) {
        coordinator.dismantleCount += 1
    }
}
