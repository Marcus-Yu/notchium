import AppKit
import SwiftUI
import XCTest
@testable import NotchiumMediaFeature
import NotchiumDynamicIsland
import NotchiumServices

@MainActor final class WaveformAppearanceTests: XCTestCase {
    func testHexInputNormalizesSupportedFormatsAndRejectsInvalidValues() {
        XCTAssertEqual(WaveformColor(hex: "  #aB12fF\n")?.hex, "#AB12FF")
        XCTAssertEqual(WaveformColor(hex: "0af")?.hex, "#00AAFF")
        XCTAssertEqual(WaveformColor(hex: "#000"), .black)
        XCTAssertEqual(WaveformColor(hex: "FFFFFF"), .white)
        for invalid in ["", "#", "12", "1234", "12345", "1234567", "#GGFFFF", "0xFF00FF", "#FFFFFFFF", "#12 456"] {
            XCTAssertNil(WaveformColor(hex: invalid), invalid)
        }
        let appearance = WaveformAppearanceModel()
        XCTAssertTrue(appearance.setStaticHex("#0af"))
        XCTAssertFalse(appearance.setStaticHex("#invalid"))
        XCTAssertEqual(appearance.staticColor.hex, "#00AAFF")
    }

    func testPreferencesRestoreModeAndRetainStaticColourAcrossAdaptiveMode() throws {
        let suite = "Notchium.WaveformAppearanceTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let appearance = WaveformAppearanceModel(preferences: preferences)
        XCTAssertEqual(appearance.mode, .static)
        XCTAssertEqual(appearance.resolvedColor, .white)
        appearance.setStaticHex("#123456")
        appearance.mode = .adaptive
        let restored = WaveformAppearanceModel(preferences: preferences)
        XCTAssertEqual(restored.mode, .adaptive)
        XCTAssertEqual(restored.resolvedColor, .white)
        restored.mode = .static
        XCTAssertEqual(restored.staticColor.hex, "#123456")
        XCTAssertGreaterThanOrEqual(restored.resolvedColor.contrastAgainstBlack, 4.5)
        XCTAssertEqual(preferences.string(forKey: "media.waveform.staticColor"), "#123456")
        preferences.set("unknown", forKey: "media.waveform.colorMode")
        preferences.set("bad colour", forKey: "media.waveform.staticColor")
        let repaired = WaveformAppearanceModel(preferences: preferences)
        XCTAssertEqual(repaired.mode, .static)
        XCTAssertEqual(repaired.staticColor, .white)
    }

    func testDarkColoursAreBrightenedAndVisibleColoursStayUnchanged() throws {
        for hex in ["#000000", "#010101", "#123456", "#001122", "#000080", "#220000", "#102010", "#747474"] {
            let selected = try XCTUnwrap(WaveformColor(hex: hex))
            let displayed = selected.visibleOnBlack
            XCTAssertGreaterThanOrEqual(displayed.contrastAgainstBlack, 4.5, hex)
            XCTAssertNotEqual(displayed, selected, hex)
            XCTAssertGreaterThanOrEqual(displayed.red, selected.red)
            XCTAssertGreaterThanOrEqual(displayed.green, selected.green)
            XCTAssertGreaterThanOrEqual(displayed.blue, selected.blue)
            XCTAssertEqual(displayed.visibleOnBlack, displayed, "Brightness adjustment must be stable")
        }
        XCTAssertEqual(WaveformColor.black.visibleOnBlack.hex, "#757575")
        for color in [WaveformColor.white, .blue, .green, WaveformColor(hex: "#757575")!, WaveformColor(hex: "#FF0000")!] {
            XCTAssertEqual(color.visibleOnBlack, color, "Already visible colours must retain their exact RGB values")
        }
        let navy = try XCTUnwrap(WaveformColor(hex: "#001040")).visibleOnBlack
        XCTAssertGreaterThan(navy.blue, navy.green)
        XCTAssertGreaterThan(navy.green, navy.red, "Brightening should retain the colour's hue")
    }

    func testAdaptiveBrightensDarkArtworkWithoutChangingItsSampledColour() async throws {
        let artwork = try XCTUnwrap(WaveformColor(hex: "#001040"))
        let appearance = WaveformAppearanceModel(loadArtworkColor: { _ in artwork })
        appearance.staticColor = .black
        appearance.mode = .adaptive
        appearance.setArtwork(try XCTUnwrap(URL(string: "https://i.scdn.co/image/dark")))
        await drain()
        XCTAssertEqual(appearance.artworkColor, artwork)
        XCTAssertEqual(appearance.resolvedColor, artwork.visibleOnBlack)
        XCTAssertGreaterThanOrEqual(appearance.resolvedColor.contrastAgainstBlack, 4.5)
        appearance.mode = .static
        XCTAssertEqual(appearance.staticColor, .black)
        XCTAssertEqual(appearance.resolvedColor.hex, "#757575")
    }

    func testPrimaryColourSelectsDominantClusterInsteadOfAverage() throws {
        let context = try imageContext()
        context.setFillColor(sRGB(red: 1, green: 0, blue: 0))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 32))
        context.setFillColor(sRGB(red: 0, green: 0, blue: 1))
        context.fill(CGRect(x: 24, y: 0, width: 8, height: 32))
        XCTAssertEqual(WaveformColor.primaryColor(in: try XCTUnwrap(context.makeImage())),
                       WaveformColor(red: 255, green: 0, blue: 0))
    }

    func testPrimaryColourIgnoresTransparentPixelsAndPreservesOpaqueBlack() throws {
        let context = try imageContext()
        XCTAssertNil(WaveformColor.primaryColor(in: try XCTUnwrap(context.makeImage())))
        context.setFillColor(sRGB(red: 0, green: 1, blue: 0))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 32))
        XCTAssertEqual(WaveformColor.primaryColor(in: try XCTUnwrap(context.makeImage())),
                       WaveformColor(red: 0, green: 255, blue: 0))
        context.setFillColor(sRGB(red: 0, green: 0, blue: 0))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        XCTAssertEqual(WaveformColor.primaryColor(in: try XCTUnwrap(context.makeImage())), .black)
    }

    func testAdaptiveFollowsArtworkAndRejectsLatePreviousArtwork() async throws {
        let loader = ArtworkColorLoader()
        let appearance = WaveformAppearanceModel(loadArtworkColor: loader.load)
        let first = try XCTUnwrap(URL(string: "https://i.scdn.co/image/first"))
        let second = try XCTUnwrap(URL(string: "https://i.scdn.co/image/second"))
        appearance.setArtwork(first)
        await drain()
        XCTAssertTrue(loader.requests.isEmpty, "Static mode does not request a palette")
        appearance.mode = .adaptive
        await drain()
        XCTAssertEqual(loader.requests, [first])
        appearance.setArtwork(second)
        await drain()
        XCTAssertEqual(loader.requests, [first, second])
        loader.complete(second, color: .green)
        await drain()
        XCTAssertEqual(appearance.resolvedColor, .green)
        loader.complete(first, color: .blue)
        await drain()
        XCTAssertEqual(appearance.resolvedColor, .green)
        appearance.setArtwork(second)
        await drain()
        XCTAssertEqual(loader.requests.count, 2, "Progress updates do not repeat artwork analysis")
        appearance.setArtwork(nil)
        XCTAssertEqual(appearance.resolvedColor, .white)
    }

    func testTrackChangesRetainPreviousColourUntilLatestArtworkIsReady() async throws {
        let loader = ArtworkColorLoader()
        let appearance = WaveformAppearanceModel(loadArtworkColor: loader.load)
        appearance.mode = .adaptive
        let first = try XCTUnwrap(URL(string: "https://i.scdn.co/image/first"))
        let second = try XCTUnwrap(URL(string: "https://i.scdn.co/image/second"))
        let third = try XCTUnwrap(URL(string: "https://i.scdn.co/image/third"))
        appearance.setArtwork(first)
        XCTAssertEqual(appearance.resolvedColor, .white, "First use keeps the default until a colour is available")
        await drain()
        loader.complete(first, color: .blue)
        await drain()

        appearance.setArtwork(second)
        XCTAssertEqual(appearance.resolvedColor, .blue, "Changing artwork must not introduce a white frame")
        await drain()
        XCTAssertEqual(loader.requests, [first, second], "The retained colour must not prevent loading the next album")
        XCTAssertEqual(appearance.resolvedColor, .blue)

        appearance.setArtwork(third)
        await drain()
        loader.complete(second, color: .green)
        await drain()
        XCTAssertEqual(appearance.resolvedColor, .blue, "A cancelled album must not replace the retained colour")
        loader.complete(third, color: .black)
        await drain()
        XCTAssertEqual(appearance.resolvedColor, WaveformColor.black.visibleOnBlack)
        appearance.setArtwork(third)
        await drain()
        XCTAssertEqual(loader.requests, [first, second, third])
        appearance.setArtwork(nil)
        XCTAssertEqual(appearance.resolvedColor, .white)
    }

    func testArtworkChangedInStaticModeLoadsLatestColourWhenAdaptiveResumes() async throws {
        let loader = ArtworkColorLoader()
        let appearance = WaveformAppearanceModel(loadArtworkColor: loader.load)
        appearance.mode = .adaptive
        let first = try XCTUnwrap(URL(string: "https://i.scdn.co/image/first"))
        let second = try XCTUnwrap(URL(string: "https://i.scdn.co/image/second"))
        appearance.setArtwork(first)
        await drain()
        loader.complete(first, color: .green)
        await drain()
        appearance.staticColor = .black
        appearance.mode = .static
        appearance.setArtwork(second)
        await drain()
        XCTAssertEqual(loader.requests, [first])
        XCTAssertEqual(appearance.resolvedColor, WaveformColor.black.visibleOnBlack)
        appearance.mode = .adaptive
        XCTAssertEqual(appearance.resolvedColor, .green)
        await drain()
        XCTAssertEqual(loader.requests, [first, second])
        loader.complete(second, color: .blue)
        await drain()
        XCTAssertEqual(appearance.resolvedColor, .blue)
        appearance.mode = .static
        appearance.mode = .adaptive
        await drain()
        XCTAssertEqual(loader.requests, [first, second], "The current album's successful palette stays reusable")
    }

    func testFailedNewArtworkUsesFallbackAfterRetainingPreviousColourWhileLoading() async throws {
        let loader = ArtworkColorLoader()
        let appearance = WaveformAppearanceModel(loadArtworkColor: loader.load)
        appearance.mode = .adaptive
        let first = try XCTUnwrap(URL(string: "https://i.scdn.co/image/first"))
        let second = try XCTUnwrap(URL(string: "https://i.scdn.co/image/failed"))
        appearance.setArtwork(first)
        await drain()
        loader.complete(first, color: .blue)
        await drain()
        appearance.setArtwork(second)
        await drain()
        XCTAssertEqual(appearance.resolvedColor, .blue)
        loader.complete(second, color: nil)
        await drain()
        XCTAssertEqual(appearance.resolvedColor, .white, "A confirmed missing palette retains the documented fallback")
    }

    func testMissingFailedAndCancelledArtworkKeepFallbackOrStaticColour() async throws {
        let loader = ArtworkColorLoader()
        let appearance = WaveformAppearanceModel(loadArtworkColor: loader.load)
        let url = try XCTUnwrap(URL(string: "https://i.scdn.co/image/failed"))
        appearance.staticColor = .black
        appearance.mode = .adaptive
        XCTAssertEqual(appearance.resolvedColor, .white)
        appearance.setArtwork(url)
        await drain()
        loader.complete(url, color: nil)
        await drain()
        XCTAssertEqual(appearance.resolvedColor, .white)
        appearance.mode = .static
        XCTAssertEqual(appearance.resolvedColor, WaveformColor.black.visibleOnBlack)
        appearance.mode = .adaptive
        await drain()
        appearance.mode = .static
        loader.complete(url, color: .green)
        await drain()
        XCTAssertEqual(appearance.resolvedColor, WaveformColor.black.visibleOnBlack)
        XCTAssertNil(appearance.artworkColor)
    }

    func testMediaPresentationUpdatesArtworkAndStopCancelsColour() async throws {
        let loader = ArtworkColorLoader()
        let appearance = WaveformAppearanceModel(loadArtworkColor: loader.load)
        appearance.mode = .adaptive
        let coordinator = DynamicIslandPresentationModel().activityCoordinator
        let model = MediaSessionController(provider: MockMediaProvider(), coordinator: coordinator,
                                           waveformAppearance: appearance)
        let url = try XCTUnwrap(URL(string: "https://i.scdn.co/image/current"))
        model.receive(MediaState(connectionState: .authenticated, playbackState: .playing,
                                 title: "Track", artwork: url, source: .spotify))
        await drain()
        XCTAssertEqual(loader.requests, [url])
        loader.complete(url, color: .blue)
        await drain()
        let next = try XCTUnwrap(URL(string: "https://i.scdn.co/image/next"))
        model.receive(MediaState(connectionState: .authenticated, playbackState: .playing,
                                 title: "Next track", artwork: next, source: .spotify))
        XCTAssertEqual(appearance.resolvedColor, .blue, "Media presentation must retain colour during a track change")
        await drain()
        XCTAssertEqual(loader.requests, [url, next])
        model.stop()
        loader.complete(next, color: .green)
        await drain()
        XCTAssertEqual(appearance.resolvedColor, .white)
    }

    func testWaveformRendersVisibleStaticAndAdaptiveColoursOnBlack() async throws {
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true })
        meter.setPlaying(true)
        await drain()
        capture.levels?(Array(repeating: 1, count: 7))
        await drain()
        defer { meter.stop() }
        for mode in WaveformColorMode.allCases {
            for selected in [WaveformColor.green, .black, WaveformColor(hex: "#001040")!] {
                let appearance = WaveformAppearanceModel(loadArtworkColor: { _ in selected })
                appearance.staticColor = selected
                appearance.mode = mode
                appearance.setArtwork(try XCTUnwrap(URL(string: "https://i.scdn.co/image/render")))
                await drain()
                let renderer = ImageRenderer(content: MediaWaveform(isPlaying: true, meter: meter, color: appearance.color)
                    .environment(\.notchReduceMotionOverride, false).frame(width: 80, height: 40).background(.black))
                renderer.scale = 4
                let image = try XCTUnwrap(renderer.cgImage)
                let context = try imageContext(width: image.width, height: image.height)
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                XCTAssertTrue((0..<(image.width * image.height)).contains { index in
                    WaveformColor(red: pixels[index * 4], green: pixels[index * 4 + 1], blue: pixels[index * 4 + 2]) == appearance.resolvedColor
                }, "\(mode) \(selected.hex): rendered bars must use the visible colour")
                XCTAssertGreaterThanOrEqual(appearance.resolvedColor.contrastAgainstBlack, 4.5)
                let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                let filename = "notchium-waveform-\(mode.rawValue)-\(selected.hex.dropFirst()).png"
                try png.write(to: URL(fileURLWithPath: "/private/tmp/\(filename)"))
            }
        }
    }

    func testSettingsRenderInBothModesAndAppearances() async throws {
        _ = NSApplication.shared
        for mode in WaveformColorMode.allCases {
            for dark in [false, true] {
                let appearance = WaveformAppearanceModel()
                appearance.mode = mode
                let host = NSHostingView(rootView: Form {
                    WaveformAppearanceSettings(appearance: appearance)
                }.formStyle(.grouped).frame(width: 480, height: 320))
                let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 480, height: 320),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                window.orderFront(nil)
                await drain()
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let filename = "notchium-waveform-settings-\(mode.rawValue)-\(dark ? "dark" : "light").png"
                try png.write(to: URL(fileURLWithPath: "/private/tmp/\(filename)"))
                XCTAssertGreaterThan(png.count, 1000)
            }
        }
    }

    private func imageContext(width: Int = 32, height: Int = 32) throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    private func sRGB(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, 1])!
    }

    private func drain() async { for _ in 0..<40 { await Task.yield() } }
}

@MainActor private final class ArtworkColorLoader {
    private(set) var requests: [URL] = []
    private var pending: [URL: CheckedContinuation<WaveformColor?, Never>] = [:]
    func load(_ url: URL) async -> WaveformColor? {
        requests.append(url)
        return await withCheckedContinuation { pending[url] = $0 }
    }
    func complete(_ url: URL, color: WaveformColor?) { pending.removeValue(forKey: url)?.resume(returning: color) }
}
