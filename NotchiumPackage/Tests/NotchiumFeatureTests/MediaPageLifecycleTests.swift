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

    func testClosingMediaKeepsPlayerOnReopen() async throws {
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
        visibility.expanded = false
        try await settle(host)
        visibility.expanded = true
        try await settle(host)
        XCTAssertGreaterThan(try playbackIconPixels(in: host), 10,
            "Reopening Media retains the player controls")
    }

    func testCompactPlayerLayoutStaysStableAcrossMetadataAndPlaybackStates() async throws {
        let base = MediaState(playbackState: .playing, title: "Midnight City", artist: "M83",
            elapsed: 48, duration: 244, artwork: URL(string: "notchium-fixture://artwork/midnight"),
            source: .spotify, capabilities: .init(canPlayPause: true, canSeek: true, canSetVolume: true))
        var long = base
        long.title = String(repeating: "A Very Long Track Title ", count: 8)
        long.artist = String(repeating: "A Very Long Artist Name ", count: 8)
        var noArtwork = base
        noArtwork.artwork = nil
        var paused = base
        paused.playbackState = .paused

        for height: CGFloat in [202, 196] {
            var referenceFrames: [CGRect]?
            for (name, state) in [("playing", base), ("long-metadata", long),
                                  ("no-artwork", noArtwork), ("paused", paused)] {
                let clock = TestAppClock(now: .now, automaticallyAdvances: false)
                let model = MediaFeatureModel(provider: MockMediaProvider(snapshot: state),
                    coordinator: ActivityCoordinator(clock: clock), visibilityClock: clock)
                model.receive(state)
                let host = NSHostingView(rootView: MediaPageView(model: model)
                    .frame(width: 524, height: height).background(Color.black)
                    .environment(\.colorScheme, .dark))
                let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 524, height: height),
                    styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.orderBack(nil)
                defer { window.close(); model.stop() }
                try await settle(host)

                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                // Inspect actual native pixels; ImageRenderer cannot render the slider's AppKit input view.
                let frames = try [
                    inkBounds(in: bitmap, region: CGRect(x: 30, y: 0, width: 84, height: 102)),
                    inkBounds(in: bitmap, region: CGRect(x: 245, y: 100, width: 35, height: 46)),
                    inkBounds(in: bitmap, region: CGRect(x: 30, y: height - 50, width: 414, height: 40),
                        neutralOnly: true),
                    inkBounds(in: bitmap, region: CGRect(x: 460, y: height - 50, width: 34, height: 40)),
                ]
                for frame in frames {
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThan(frame.height, 0)
                    XCTAssertTrue(host.bounds.contains(frame), "\(name): control outside the Media page: \(frame)")
                }
                if let referenceFrames {
                    XCTAssertEqual(frames, referenceFrames,
                        "Long metadata, missing artwork, and paused playback must preserve control positions")
                } else {
                    referenceFrames = frames
                }
                XCTAssertEqual(frames[0].height, 84, accuracy: 1, "Artwork uses the freed player space")
                XCTAssertGreaterThanOrEqual(frames[0].minY, 8)
                XCTAssertLessThanOrEqual(frames[0].minY, 16, "The player has no empty selector band")
                XCTAssertGreaterThanOrEqual(frames[1].minY - frames[0].maxY, 10)
                XCTAssertLessThanOrEqual(frames[1].minY - frames[0].maxY, 16,
                    "Artwork and transport have a compact, even gap")
                XCTAssertGreaterThan(frames[2].minY, frames[1].maxY, "Volume stays below transport")
                XCTAssertLessThanOrEqual(frames[2].minY - frames[1].maxY, 28,
                    "Volume fills the former section-navigation space")
                XCTAssertGreaterThan(frames[2].width, 380, "Volume uses the full footer width")
                XCTAssertGreaterThanOrEqual(height - frames[2].maxY, 12)
                XCTAssertLessThanOrEqual(height - frames[2].maxY, 30,
                    "Volume's smaller glyphs stay centered in the bottom row")
                XCTAssertEqual(frames[2].midY, frames[3].midY, accuracy: 2,
                    "Volume and the source logo share the same row")
                XCTAssertEqual(frames[3].maxX, 494, accuracy: 1, "The source logo aligns with the page gutter")

                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-media-spacing-\(name)-\(Int(height)).png"))
            }
        }
    }

    private func inkBounds(in bitmap: NSBitmapImageRep, region: CGRect, neutralOnly: Bool = false) throws -> CGRect {
        let scale = CGFloat(bitmap.pixelsWide) / 524
        var bounds = CGRect.null
        for y in Int(region.minY * scale)..<Int(region.maxY * scale) {
            for x in Int(region.minX * scale)..<Int(region.maxX * scale) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      max(color.redComponent, color.greenComponent, color.blueComponent) > 0.025 else { continue }
                // Ignore colored artwork when measuring the neutral volume control.
                if neutralOnly && (abs(color.redComponent - color.greenComponent) > 0.01
                    || abs(color.greenComponent - color.blueComponent) > 0.01) { continue }
                bounds = bounds.union(CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale,
                    width: 1 / scale, height: 1 / scale))
            }
        }
        XCTAssertFalse(bounds.isNull, "Expected visible content in \(region)")
        return bounds
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
