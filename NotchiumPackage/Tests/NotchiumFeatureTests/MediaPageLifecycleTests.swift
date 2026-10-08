import AppKit
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import SwiftUI
import XCTest
@testable import NotchiumMediaFeature

@MainActor @Observable
private final class MediaPageVisibility {
    var expanded = true
}

private struct MediaPageHarness: View {
    let model: MediaFeatureModel
    let visibility: MediaPageVisibility

    var body: some View {
        MediaPageView(model: model)
            .environment(\.notchMediaExpanded, visibility.expanded)
            .environment(\.notchMediaPageVisible, visibility.expanded)
    }
}

@MainActor
final class MediaPageLifecycleTests: XCTestCase {
    private func makeModel() -> MediaFeatureModel {
        let state = MediaState(playbackState: .paused, title: "Fixture", artist: "Artist",
            elapsed: 20, duration: 240, source: .spotify,
            capabilities: .init(canPlayPause: true, canSeek: true, canReadQueue: true),
            queue: [.init(id: "upcoming", title: "Upcoming", artist: "Artist")])
        let clock = TestAppClock(now: .now, automaticallyAdvances: false)
        let model = MediaFeatureModel(provider: MockMediaProvider(snapshot: state),
            coordinator: ActivityCoordinator(clock: clock), visibilityClock: clock)
        model.receive(state)
        return model
    }

    func testSpotifyArtworkAlignsWithRightContentEdge() throws {
        let model = makeModel()
        defer { model.stop() }
        let renderer = ImageRenderer(content: MediaPageView(model: model)
            .frame(width: 524, height: 196).background(Color.black))
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        var rightmostGreenPixel = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.greenComponent > 0.5 && color.redComponent < 0.2 {
                    rightmostGreenPixel = max(rightmostGreenPixel, x)
                }
            }
        }
        XCTAssertEqual(rightmostGreenPixel, 493, accuracy: 2,
            "The logo artwork aligns with the 30 pt page gutter, including its transparent image border")
    }

    func testClosingUpNextReturnsToCurrentlyPlayingOnReopen() async throws {
        let model = makeModel()
        let visibility = MediaPageVisibility()
        let host = NSHostingView(rootView: MediaPageHarness(model: model, visibility: visibility)
            .frame(width: 524, height: 196).background(Color.black))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 524, height: 196),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close(); model.stop() }
        try await settle(host)

        XCTAssertGreaterThan(try playbackIconPixels(in: host), 10)
        // Native window coordinates: the Up Next button is at the upper right.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 458, y: 176),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
        }
        try await settle(host)
        XCTAssertEqual(try playbackIconPixels(in: host), 0, "Up Next replaces the player controls")

        visibility.expanded = false
        try await settle(host)
        visibility.expanded = true
        try await settle(host)
        XCTAssertGreaterThan(try playbackIconPixels(in: host), 10,
            "Reopening Media shows Currently Playing rather than the previous queue")
    }

    private func settle(_ host: NSView) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    private func playbackIconPixels(in host: NSView) throws -> Int {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = bitmap.pixelsWide / 524
        var whitePixels = 0
        for y in (120 * scale)..<(152 * scale) {
            for x in (245 * scale)..<(280 * scale) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.8 {
                    whitePixels += 1
                }
            }
        }
        return whitePixels
    }
}
