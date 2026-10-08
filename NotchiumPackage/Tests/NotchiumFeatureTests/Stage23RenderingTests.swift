import AppKit
import NotchiumCore
import NotchiumDesignSystem
@testable import NotchiumCalendarFeature
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature
import NotchiumServices
import SwiftUI
import XCTest

@MainActor
final class Stage23RenderingTests: XCTestCase {
    func testIncreaseContrastBrightensTheUnfilledSliderTrack() async throws {
        func trackBrightness(increased: Bool) async throws -> CGFloat {
            let slider = NotchiumSlider(value: .constant(0.25), accessibilityLabel: "Volume",
                accessibilityStep: 0.05, accessibilityValue: { "\(Int($0 * 100)) percent" })
                .frame(width: 200, height: 24)
                .environment(\.notchIncreaseContrastOverride, increased)
                .environment(\.notchReduceTransparencyOverride, false)
                .background(Color.black)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
            let host = NSHostingView(rootView: AnyView(slider))
            host.frame = CGRect(x: 0, y: 0, width: 200, height: 24)
            let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 200, height: 24),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            host.appearance = NSAppearance(named: .darkAqua)
            window.appearance = host.appearance
            window.contentView = host
            window.orderBack(nil)
            defer { window.close() }

            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            let scale = image.pixelsWide / 200
            return try averageRed(in: image, x: (145 * scale)..<(156 * scale), y: (11 * scale)..<(13 * scale))
        }

        let standard = try await trackBrightness(increased: false)
        let increased = try await trackBrightness(increased: true)

        XCTAssertLessThan(standard, 0.35, "The unfilled track stays subtle at standard contrast")
        XCTAssertGreaterThan(increased, 0.4, "Increase Contrast must make the unfilled track easy to find")
        XCTAssertGreaterThan(increased, standard + 0.2)
    }

    func testReduceMotionOverridePropagatesToTheMediaWaveform() async throws {
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true })
        defer { meter.stop() }
        meter.setPlaying(true)
        for _ in 0..<100 where capture.levels == nil { await Task.yield() }
        capture.levels?(Array(repeating: 0.9, count: 7))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(meter.isAudioActive)

        let ordinary = try render(
            MediaWaveform(isPlaying: true, meter: meter)
                .environment(\.notchReduceMotionOverride, false),
            size: CGSize(width: 24, height: 16))
        let reduced = try render(
            MediaWaveform(isPlaying: true, meter: meter)
                .environment(\.notchReduceMotionOverride, true),
            size: CGSize(width: 24, height: 16))
        let hidden = try render(
            MediaWaveform(isPlaying: true, meter: meter, isPresented: false)
                .environment(\.notchReduceMotionOverride, false),
            size: CGSize(width: 24, height: 16))

        XCTAssertGreaterThan(whitePixelCount(in: ordinary), 20, "The active waveform is visible normally")
        XCTAssertEqual(whitePixelCount(in: reduced), 0, "The inherited override suppresses waveform motion")
        XCTAssertEqual(whitePixelCount(in: hidden), 0, "A hidden page does not render the active waveform")
        XCTAssertTrue(meter.isRunning, "Presentation visibility must not stop local playback detection")
    }

    func testReduceTransparencyOverrideChangesTheCalendarJoinMaterial() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let calendar = CalendarActivityModel(service: MockCalendarService(),
            coordinator: ActivityCoordinator(clock: clock), clock: clock)
        defer { calendar.stop() }
        await calendar.reminders.update(events: [CalendarEventSummary(
            id: UUID(), title: "Regional planning review", startDate: now.addingTimeInterval(1_800),
            endDate: now.addingTimeInterval(5_400),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"))])
        XCTAssertEqual(calendar.reminders.current?.isImminent, false)

        func renderJoin(override: Bool) throws -> NSBitmapImageRep {
            try render(CalendarReminderView(model: calendar, openActivity: {})
                .environment(\.notchReduceTransparencyOverride, override),
                size: CGSize(width: 356, height: 88))
        }
        let standard = try renderJoin(override: false)
        let reduced = try renderJoin(override: true)

        XCTAssertGreaterThan(pixelDifferenceCount(standard, reduced), 20,
            "The inherited override replaces the translucent glass treatment with a solid backing")
    }

    func testLongMediaMetadataStaysWithinThePlayerViewport() throws {
        let cases = [
            ("Midnight City", "M83"),
            ("A Regional Orchestra Recording of the Complete Symphonic Works, Volume Twelve",
             "The North American Chamber Orchestra and the International Festival Chorus")
        ]
        for (index, metadata) in cases.enumerated() {
            let model = MediaFeatureModel(provider: MockMediaProvider(),
                coordinator: ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false)))
            defer { model.stop() }
            model.receive(.init(playbackState: .playing, title: metadata.0, artist: metadata.1,
                elapsed: 92, duration: 225, trackID: "stage23-\(index)", source: .spotify,
                capabilities: .init(canPlayPause: true, canSkipForward: true,
                    canSkipBackward: true, canSeek: true)))
            let image = try render(MediaPageView(model: model), size: CGSize(width: 524, height: 196))

            XCTAssertEqual(image.pixelsWide, 524, "Long metadata must not widen the player")
            XCTAssertEqual(image.pixelsHigh, 196, "Long metadata must not increase the player height")
            XCTAssertEqual(nonBlackPixels(in: image, x: 0..<8) + nonBlackPixels(in: image, x: 516..<524), 0,
                "Long metadata must truncate inside the padded player content")
            XCTAssertGreaterThan(nonBlackPixels(in: image, x: 24..<500), 100,
                "The player remains rendered when metadata is long")
        }
    }

    private func render<V: View>(_ view: V, size: CGSize) throws -> NSBitmapImageRep {
        let content = view
            .frame(width: size.width, height: size.height)
            .foregroundStyle(.white)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    private func averageRed(in image: NSBitmapImageRep, x: Range<Int>, y: Range<Int>) throws -> CGFloat {
        var total: CGFloat = 0
        var count = 0
        for row in y {
            for column in x {
                let color = try XCTUnwrap(image.colorAt(x: column, y: row)?.usingColorSpace(.sRGB))
                total += color.redComponent
                count += 1
            }
        }
        return total / CGFloat(count)
    }

    private func whitePixelCount(in image: NSBitmapImageRep) -> Int {
        (0..<image.pixelsHigh).reduce(into: 0) { count, y in
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9 {
                    count += 1
                }
            }
        }
    }

    private func nonBlackPixels(in image: NSBitmapImageRep, x: Range<Int>) -> Int {
        (0..<image.pixelsHigh).reduce(into: 0) { count, y in
            for column in x {
                guard let color = image.colorAt(x: column, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent > 0.05 || color.greenComponent > 0.05 || color.blueComponent > 0.05 {
                    count += 1
                }
            }
        }
    }

    private func pixelDifferenceCount(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Int {
        guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return .max }
        var differences = 0
        for y in 0..<lhs.pixelsHigh {
            for x in 0..<lhs.pixelsWide {
                guard let a = lhs.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let b = rhs.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let distance = abs(a.redComponent - b.redComponent)
                    + abs(a.greenComponent - b.greenComponent)
                    + abs(a.blueComponent - b.blueComponent)
                if distance > 0.08 { differences += 1 }
            }
        }
        return differences
    }
}
