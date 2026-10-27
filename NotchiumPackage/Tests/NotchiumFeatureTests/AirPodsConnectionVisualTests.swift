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

        func assertTurns(_ prefix: String, connected: Bool = false, firstFrame: Int = 14,
                         secondFrame: Int = 22) throws {
            let first = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf:
                output.appendingPathComponent(String(format: "%@-%02d.png", prefix, firstFrame)))))
            let second = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf:
                output.appendingPathComponent(String(format: "%@-%02d.png", prefix, secondFrame)))))
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
            XCTAssertGreaterThan(changed, 20, "\(prefix): the product must keep rotating while its banner is visible")
        }

        func productInk(_ data: Data, connected: Bool) throws -> (ink: Double, center: Double) {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            let scale = CGFloat(bitmap.pixelsWide) / layout.panelFrame.width
            let start = try glyphColumns(connected: connected, pixelsWide: bitmap.pixelsWide).lowerBound
            let end = Int(layout.panelFrame.width / 2 * scale)
            var ink = 0.0
            var weightedX = 0.0
            for y in 0..<Int(layout.collapsedVisibleFrame.height * scale) {
                for x in start..<end {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    // The media fixture is pure red, so it cannot count as white product ink.
                    guard abs(color.redComponent - color.greenComponent) < 0.1,
                          abs(color.greenComponent - color.blueComponent) < 0.1 else { continue }
                    let white = min(color.redComponent, color.greenComponent, color.blueComponent)
                    if white > 0.02 {
                        ink += white
                        weightedX += white * Double(x) / Double(scale)
                    }
                }
            }
            return (ink, ink > 0 ? weightedX / ink : 0)
        }

        func assertSoftExit(_ prefix: String, connected: Bool, count: Int, reduced: Bool = false) throws {
            var samples: [(ink: Double, center: Double)] = []
            for index in 0..<count {
                samples.append(try productInk(Data(contentsOf: output.appendingPathComponent(
                    String(format: "%@-%02d.png", prefix, index))), connected: connected))
            }
            let first = try XCTUnwrap(samples.first)
            XCTAssertGreaterThan(first.ink, 30, "\(prefix): dismissal must begin with visible artwork")
            let fading = samples.filter { $0.ink > first.ink * 0.04 && $0.ink < first.ink * 0.9 }
            XCTAssertGreaterThanOrEqual(fading.count, reduced ? 1 : 3,
                                        "\(prefix): the exit must fade across several rendered frames")
            for sample in samples.suffix(2) {
                XCTAssertLessThan(sample.ink, first.ink * 0.01, "\(prefix): no product may linger or pop back")
            }
            if reduced {
                for sample in fading {
                    XCTAssertEqual(sample.center, first.center, accuracy: 2,
                                   "Reduce Motion fades the product in place")
                }
            } else {
                XCTAssertGreaterThan(fading.map(\.center).max() ?? 0, first.center + 12,
                                     "\(prefix): the rotating product must glide inward before disappearing")
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        _ = try capture("00-rest")
        model.notificationCoordinator.present(event(connected: true))
        try await frames("01-connect", count: 61)
        try assertTurns("01-connect", connected: true, firstFrame: 43, secondFrame: 53)
        _ = try capture("02-still-turning")

        // Same artwork/name/connected state and same coalesced banner: switching the route
        // to another pair, or explicitly selecting it, must leave the loop running.
        model.showAudioHUD(.init(kind: .outputChanged, deviceName: "AirPods Pro", volume: 0.5,
            isMuted: false, deviceStyle: .airPodsPro, deviceID: "other-pods",
            battery: .init(level: 0.82, isCharging: false)))
        try await frames("02b-manual-other-pair", count: 34)
        try assertTurns("02b-manual-other-pair", connected: true)
        model.showAudioHUD(.init(kind: .outputChanged, deviceName: "AirPods Pro", volume: 0.5,
            isMuted: false, deviceStyle: .airPodsPro, deviceID: "other-pods",
            battery: .init(level: 0.82, isCharging: false), transitionRevision: 1))
        try await frames("02c-manual-same-pair", count: 34)
        try assertTurns("02c-manual-same-pair", connected: true)

        // The same coalesced activity turns back on disconnect and forward on reconnect.
        model.notificationCoordinator.present(event(connected: false))
        try await frames("03-disconnect", count: 61)
        try assertTurns("03-disconnect")
        try assertTurns("03-disconnect", firstFrame: 43, secondFrame: 53)
        model.notificationCoordinator.present(event(connected: true))
        try await frames("04-reconnect", count: 9)
        model.notificationCoordinator.present(event(connected: false))
        try await frames("04b-reverse-during-turn", count: 6)
        model.notificationCoordinator.present(event(connected: true))
        try await frames("04c-reconnect-during-turn", count: 6)
        model.setReduceMotion(true)
        try await Task.sleep(for: .milliseconds(150))
        let reduced = try capture("05-reduced")
        try await Task.sleep(for: .milliseconds(150))
        let stillReduced = try capture("05b-still-reduced")
        let reducedBitmap = try XCTUnwrap(NSBitmapImageRep(data: reduced))
        let stillReducedBitmap = try XCTUnwrap(NSBitmapImageRep(data: stillReduced))
        // Check the product itself: shell-mask alpha and the tiny charge arc can still settle
        // independently. The product itself must remain still with Reduce Motion enabled.
        let columns = try glyphColumns(connected: true, pixelsWide: reducedBitmap.pixelsWide)
        for y in 0..<80 {
            for x in columns {
                let first = try XCTUnwrap(reducedBitmap.colorAt(x: x, y: y))
                let last = try XCTUnwrap(stillReducedBitmap.colorAt(x: x, y: y))
                XCTAssertEqual(first.redComponent, last.redComponent, accuracy: 0.01)
                XCTAssertEqual(first.greenComponent, last.greenComponent, accuracy: 0.01)
                XCTAssertEqual(first.blueComponent, last.blueComponent, accuracy: 0.01)
            }
        }
        model.setReduceMotion(false)
        try await frames("06-motion-restored", count: 61)
        try assertTurns("06-motion-restored", connected: true, firstFrame: 43, secondFrame: 53)

        model.notificationCoordinator.dismissByUser()
        try await frames("07-exit", count: 12)
        _ = try capture("08-restored")

        model.notificationCoordinator.present(event(connected: false))
        try await frames("08b-fresh-disconnect", count: 61)
        try assertTurns("08b-fresh-disconnect", firstFrame: 43, secondFrame: 53)
        model.notificationCoordinator.dismissByUser()
        try await Task.sleep(for: .milliseconds(500))

        for style in [NotchDeviceStyle.airPods, .airPodsMax] {
            model.notificationCoordinator.present(event(connected: true, style: style))
            try await frames("09-\(style.rawValue)", count: 61)
            try assertTurns("09-\(style.rawValue)", connected: true, firstFrame: 43, secondFrame: 53)
            model.notificationCoordinator.dismissByUser()
            try await Task.sleep(for: .milliseconds(500))
        }

        // Returning after preemption suppresses the entrance flourish, never the active loop.
        model.notificationCoordinator.present(event(connected: true))
        try await Task.sleep(for: .milliseconds(600))
        model.notificationCoordinator.present(.lowBattery(level: 0.1))
        try await Task.sleep(for: .milliseconds(600))
        model.notificationCoordinator.dismissByUser()
        try await frames("10-restored-banner", count: 61)
        try assertTurns("10-restored-banner", connected: true, firstFrame: 43, secondFrame: 53)

        // Expiry stays with the activity coordinator; the glyph adds no second lifetime.
        await clock.advance(by: .seconds(3))
        try await frames("11-expiry", count: 12)
        XCTAssertNil(model.collapsedRowNotification)

        // Validate the final flight into the notch, including the earlier Music-yield cutoff.
        let media = AirPodsExitMediaFixture()
        for restoresMedia in [false, true] {
            if restoresMedia {
                model.mediaRenderer = media
                model.activityCoordinator.present(.init(id: UUID(), key: .media, kind: .media,
                    title: "Fixture playback", subtitle: nil, priority: .low, presentationStyle: .mediaSides,
                    lifetime: .persistent, isDismissible: false, duration: nil,
                    payload: .mediaPlayback(isPlaying: true), minimal: .artwork))
            }
            for connected in [true, false] {
                let prefix = "12-exit-\(connected ? "connect" : "disconnect")-\(restoresMedia ? "music" : "idle")"
                model.notificationCoordinator.present(event(connected: connected))
                try await Task.sleep(for: .milliseconds(650))
                model.notificationCoordinator.dismissByUser()
                XCTAssertEqual(model.showsCollapsedMedia, restoresMedia)
                try await frames(prefix, count: 18, interval: .milliseconds(30))
                try assertSoftExit(prefix, connected: connected, count: 18)
            }
        }
        model.setReduceMotion(true)
        model.notificationCoordinator.present(event(connected: true))
        try await Task.sleep(for: .milliseconds(650))
        model.notificationCoordinator.dismissByUser()
        try await frames("13-reduced-exit", count: 12, interval: .milliseconds(30))
        try assertSoftExit("13-reduced-exit", connected: true, count: 12, reduced: true)

        model.setReduceMotion(false)
        model.activityCoordinator.dismiss(key: .media)
        model.mediaRenderer = nil
        try await Task.sleep(for: .milliseconds(500))
        model.notificationCoordinator.present(event(connected: true))
        try await Task.sleep(for: .milliseconds(140))
        let entering = try productInk(capture("14-entering"), connected: true)
        model.notificationCoordinator.dismissByUser()
        let reversing = try productInk(capture("14-reversing-to-exit"), connected: true)
        XCTAssertGreaterThan(entering.ink, 30)
        XCTAssertEqual(reversing.center, entering.center, accuracy: 5,
                       "Early dismissal must preserve the live position")
        XCTAssertEqual(reversing.ink, entering.ink, accuracy: entering.ink * 0.3,
                       "Early dismissal must not jump onto a dimmer exit curve")
        try await frames("14-early-exit", count: 3, interval: .milliseconds(20))
        let leaving = try productInk(capture("15-leaving"), connected: true)
        model.notificationCoordinator.present(event(connected: true, revision: 1))
        let reopening = try productInk(capture("15-reopening"), connected: true)
        XCTAssertEqual(reopening.center, leaving.center, accuracy: 5,
                       "A new connection during exit must reverse from the live position")
        XCTAssertEqual(reopening.ink, leaving.ink, accuracy: max(leaving.ink * 0.3, 10))
        try await frames("15-reopened", count: 20)
    }
}

@MainActor
private final class AirPodsExitMediaFixture: NotchMediaRendering {
    let collapsedMediaVisible = true
    private let artwork = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView {
        let geometry = CollapsedMediaGeometry(hardwareWidth: hardwareWidth, hardwareHeight: hardwareHeight)
        return AnyView(HStack(spacing: 0) {
            artwork.frame(width: 20, height: 20).frame(width: geometry.leadingWidth)
            Color.clear.frame(width: hardwareWidth)
            artwork.frame(width: 20, height: 10).frame(width: geometry.trailingWidth)
        }.frame(height: hardwareHeight))
    }

    func expandedMedia() -> AnyView { AnyView(EmptyView()) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(artwork.frame(width: size, height: size)) }
}
