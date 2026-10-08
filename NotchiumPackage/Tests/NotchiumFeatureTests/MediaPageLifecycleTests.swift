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
                    inkBounds(in: bitmap, region: CGRect(x: 230, y: 0, width: 170, height: 40)),
                    inkBounds(in: bitmap, region: CGRect(x: 30, y: 36, width: 76, height: 90)),
                    inkBounds(in: bitmap, region: CGRect(x: 245, y: 110, width: 35, height: 58)),
                    inkBounds(in: bitmap, region: CGRect(x: 350, y: 160, width: 144, height: height - 160),
                        neutralOnly: true),
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
                XCTAssertGreaterThanOrEqual(frames[1].minY - frames[0].maxY, height == 202 ? 11 : 5,
                    "The selector must remain separate from the artwork and metadata region")
                if height == 202 {
                    let title = try inkBounds(in: bitmap,
                        region: CGRect(x: 122, y: frames[1].minY, width: 278, height: 20))
                    // The 28 point utilities sit centered in their 32 point navigation row.
                    let upperGap = frames[0].minY + 2
                    XCTAssertEqual(title.minY - frames[0].maxY, upperGap * 2, accuracy: 1,
                        "The visible title gap is twice the utility-to-selector gap")
                }
                XCTAssertEqual(frames[1].height, 76, accuracy: 1, "Artwork retains its original size")
                XCTAssertGreaterThan(frames[3].minY, frames[2].maxY, "Output stays below transport")
                XCTAssertGreaterThanOrEqual(height - frames[3].maxY, 3, "Output stays inside the shell")

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
                // The output search also passes the green Spotify logo above the device button.
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
