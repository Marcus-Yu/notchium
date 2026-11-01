import AppKit
import NotchiumCore
import NotchiumDesignSystem
import NotchiumDynamicIsland
import NotchiumServices
import SwiftUI
import XCTest
@testable import NotchiumMediaFeature

@MainActor
final class HomeMediaLayoutTests: XCTestCase {
    func testShortAndLongTitlesKeepMetadataGroupedAndTransportStationary() throws {
        for compact in [false, true] {
            let width = 242
            let height = compact ? 140 : 196
            let artworkHeight = compact ? 56 : 72
            let inset = compact ? 4 : 8
            let metadataStart = artworkHeight + (compact ? 8 : 12)
            let model = MediaSessionController(provider: MockMediaProvider(),
                coordinator: ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false)))
            defer { model.stop() }
            var state = MediaState(playbackState: .paused, title: "Midnight City", artist: "M83",
                elapsed: 81, duration: 244, trackID: "home-layout", volumePercent: 65,
                artwork: URL(string: "notchium-fixture://artwork/home-layout"), source: .spotify,
                capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true, canSeek: true))
            model.receive(state)
            let short = try render(model, compact: compact, width: width, height: height)
            state.title = "A Walk Through the City at Midnight — The Extended Live Session"
            model.receive(state)
            let long = try render(model, compact: compact, width: width, height: height)

            for image in [short, long] {
                let titleRows = (inset..<(inset + artworkHeight)).filter { y in
                    (metadataStart..<width).contains { x in
                        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        return color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9
                    }
                }
                let titleBottom = try XCTUnwrap(titleRows.last, "Title glyphs must render in the information lane")
                // Skip the title's antialiased bottom edge before looking for the
                // secondary-color artist glyphs.
                let artistTop = try XCTUnwrap(((titleBottom + 3)..<(inset + artworkHeight)).first { y in
                    (metadataStart..<width).contains { x in
                        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        return (0.5...0.75).contains(color.redComponent)
                            && abs(color.redComponent - color.greenComponent) < 0.01
                            && abs(color.redComponent - color.blueComponent) < 0.01
                    }
                }, "Artist glyphs must remain visible below the title")
                XCTAssertLessThanOrEqual(artistTop - titleBottom, 12,
                    "An unused title line must not separate the title and artist (compact=\(compact))")
            }

            // Metadata changes must not move or redraw the playback track, times or
            // transport. Paused fixture state keeps their content deterministic.
            var changedPlaybackPixels = 0
            for y in (inset + artworkHeight + 4)..<height {
                for x in 0..<width {
                    if short.colorAt(x: x, y: y) != long.colorAt(x: x, y: y) { changedPlaybackPixels += 1 }
                }
            }
            XCTAssertEqual(changedPlaybackPixels, 0,
                "Playback layout changed with title length (compact=\(compact))")
        }
    }

    private func render(_ model: MediaSessionController, compact: Bool, width: Int, height: Int) throws -> NSBitmapImageRep {
        let view = HomeMediaView(model: model, openMusic: {})
            .frame(width: CGFloat(width), height: CGFloat(height))
            .foregroundStyle(.white)
            .background(.black)
            .environment(\.homeUsesCompactLayout, compact)
            .environment(\.colorScheme, .dark)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }
}
