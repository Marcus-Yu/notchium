import AppKit
import SwiftUI
import XCTest
@testable import NotchiumMediaFeature

@MainActor
final class MediaSourceLinkTests: XCTestCase {
    func testMediaViewButtonsRenderWhiteInLightAndDarkAppearances() throws {
        for appearance in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: MediaPageHeader(selection: .constant(.player))
                .frame(width: 464, height: 32)
                .background(Color.black)
                .environment(\.colorScheme, appearance))
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            for columns in [230..<390, 390..<464] {
                var whitePixels = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in columns {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                        if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.8 {
                            whitePixels += 1
                        }
                    }
                }
                XCTAssertGreaterThan(whitePixels, 30, "Both Media view buttons need visible white labels")
            }
        }
    }

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
