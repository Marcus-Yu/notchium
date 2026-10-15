import AppKit
import SwiftUI
import XCTest
@testable import NotchiumMediaFeature

@MainActor
final class MediaSourceLinkTests: XCTestCase {
    func testSpotifyLogoIsBundledAndVisible() throws {
        let renderer = ImageRenderer(content: MediaSourceButton(source: .spotify).background(Color.black))
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        var greenPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.greenComponent > 0.5 && color.redComponent < 0.2 { greenPixels += 1 }
            }
        }
        XCTAssertGreaterThan(greenPixels, 50, "The source button must show Spotify’s bundled logo")
    }

    func testInstalledSourceOpensApplicationWithoutOpeningFallback() {
        var opened: [URL] = []
        let action = OpenURLAction { url in
            opened.append(url)
            return .handled
        }

        MediaSourceDestination(source: .spotify).open(using: action)

        XCTAssertEqual(opened, [URL(string: "spotify:")!])
    }

    func testMissingApplicationOpensSpotifyDownloadPage() {
        var opened: [URL] = []
        let action = OpenURLAction { url in
            opened.append(url)
            return url.scheme == "spotify" ? .discarded : .handled
        }

        MediaSourceDestination(source: .spotify).open(using: action)

        XCTAssertEqual(opened, [URL(string: "spotify:")!, URL(string: "https://www.spotify.com/download/")!])
    }
}
