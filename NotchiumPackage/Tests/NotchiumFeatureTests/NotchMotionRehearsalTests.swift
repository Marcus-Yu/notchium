import AppKit
import NotchiumCore
import NotchiumDesignSystem
import NotchiumServices
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature

/// Opt-in frame rehearsal of the production shell and player over mock state.
/// Native offscreen snapshots are not hardware recordings or frame-pacing evidence.
@MainActor
final class NotchMotionRehearsalTests: XCTestCase {
    func testCaptureShellNavigationAndPlayback() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["NOTCHIUM_MOTION_CAPTURE_DIR"], !path.isEmpty else {
            throw XCTSkip("Set NOTCHIUM_MOTION_CAPTURE_DIR to rehearse native notch motion")
        }
        let variants: [Bool]
        switch environment["NOTCHIUM_MOTION_REDUCE_MOTION"] {
        case "0": variants = [false]
        case "1": variants = [true]
        default: variants = [false, true]
        }

        for reduced in variants {
            let output = URL(fileURLWithPath: path, isDirectory: true)
                .appendingPathComponent(reduced ? "reduced" : "standard", isDirectory: true)
            let fixture = try MotionRehearsalFixture(reduced: reduced)
            defer { fixture.stop() }
            let recorder = try MotionRehearsalRecorder(host: fixture.host, output: output,
                                                      reducedMotion: reduced)
            try await Task.sleep(for: .milliseconds(100))
            try recorder.capture("collapsed")

            fixture.presentation.setExpanded(true)
            fixture.presentation.pageModel.selectedPage = .music
            try await recorder.sample("open", count: 18)
            try await Task.sleep(for: .milliseconds(200))
            try recorder.capture("music-settled")

            fixture.presentation.collapse()
            try await recorder.sample("close", count: 18)
            try await Task.sleep(for: .milliseconds(200))
            try recorder.capture("collapsed-settled")

            fixture.presentation.setExpanded(true)
            try await recorder.sample("reversal-opening", count: 6)
            fixture.presentation.collapse()
            try await recorder.sample("reversal-closing", count: 6)
            fixture.presentation.setExpanded(true)
            try await recorder.sample("reversal-reopening", count: 18)
            try await Task.sleep(for: .milliseconds(200))
            try recorder.capture("reversal-settled")

            fixture.presentation.pageModel.selectedPage = .home
            try await recorder.sample("page-home", count: 12)
            try await Task.sleep(for: .milliseconds(80))
            try recorder.capture("home-settled")

            var state = fixture.media.state
            state.title = "A Walk Through the City at Midnight — The Extended Live Session"
            state.artist = "The Orchestra with a Very Long Artist Name"
            try await fixture.receive(state)
            try await recorder.sample("home-metadata-long", count: 12)
            state.title = "Midnight City"
            state.artist = "M83"
            try await fixture.receive(state)
            try await recorder.sample("home-metadata-short", count: 12)

            fixture.presentation.pageModel.selectedPage = .music
            try await recorder.sample("page-music", count: 12)

            // Retarget while a page is fading out or waiting to enter. The
            // latest selection must arrive without ghosting an obsolete page.
            for page in [NotchPage.home, .music, .home] {
                fixture.presentation.pageModel.selectedPage = page
                try await recorder.sample("page-reversal", count: 2)
            }
            fixture.presentation.pageModel.selectedPage = .music
            try await recorder.sample("page-reversal-settling", count: 12)

            state = fixture.media.state
            state.title = "A Walk Through the City at Midnight — The Extended Live Session"
            state.artist = "The Orchestra with a Very Long Artist Name"
            try await fixture.receive(state)
            try await recorder.sample("metadata-long", count: 12)
            state.title = "Midnight City"
            state.artist = "M83"
            try await fixture.receive(state)
            try await recorder.sample("metadata-short", count: 12)

            fixture.media.send(.next)
            // The mock command finishes without external I/O. Deliver its snapshot
            // explicitly; the fixture never starts the provider observation loop.
            try await recorder.sample("skip-feedback", count: 4)
            try await fixture.receive(await fixture.provider.snapshot)
            try await recorder.sample("track-change", count: 12)
            XCTAssertLessThan(fixture.media.state.elapsed, 1, "A new track resets progress directly")

            state = fixture.media.state
            state.playbackState = .paused
            state.playbackRate = 0
            state.elapsed = 42
            try await fixture.receive(state)
            try await recorder.sample("paused", count: 10)
            try await fixture.media.seek(to: 126)
            try await recorder.sample("paused-seek", count: 10)
            XCTAssertEqual(fixture.media.state.playbackState, .paused)
            XCTAssertEqual(fixture.media.state.elapsed, 126, accuracy: 0.001)
            try recorder.capture("paused-seek-settled")
            try recorder.writeReport()
        }
    }
}

@MainActor
private final class MotionRehearsalFixture {
    let provider: MockMediaProvider
    let media: MediaSessionController
    let presentation: DynamicIslandPresentationModel
    let host: NSHostingView<AnyView>
    private let window: NSWindow

    init(reduced: Bool) throws {
        let state = MediaState(playbackState: .playing, title: "Midnight City", artist: "M83",
            elapsed: 48, duration: 244, trackID: "midnight", volumePercent: 65,
            artwork: URL(string: "notchium-fixture://artwork/midnight"), source: .spotify,
            capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true,
                                canSeek: true, canShuffle: true, canRepeat: true, canSetVolume: true),
            shuffle: false, repeatMode: .off)
        provider = MockMediaProvider(snapshot: state)
        let coordinator = ActivityCoordinator(clock: ContinuousAppClock())
        media = MediaSessionController(provider: provider, coordinator: coordinator,
            audioMeter: SystemAudioMeter(captureEnabled: false), localDeviceNames: [])
        media.receive(state)
        presentation = DynamicIslandPresentationModel(activityCoordinator: coordinator)
        presentation.mediaRenderer = media
        presentation.pageModel.defaultPage = .music
        let layout = NotchGeometryResolver.layout(for:
            .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        let size = layout.panelFrame.size
        host = NSHostingView(rootView: AnyView(NotchiumShellView(model: presentation, layout: layout,
            renderConfiguration: .init(appearance: .dark, reduceMotion: reduced ? .on : .off))
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.3))))
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .darkAqua)
        window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = host
        window.orderBack(nil)
    }

    func receive(_ value: MediaState) async throws {
        var value = value
        value.timestamp = Date()
        value.sampledUptime = ProcessInfo.processInfo.systemUptime
        await provider.publish(value)
        media.receive(value)
    }

    func stop() {
        window.close()
        media.stop()
        presentation.reset()
    }
}

@MainActor
private final class MotionRehearsalRecorder {
    private struct Frame: Codable {
        let file: String
        let beat: String
        let monotonicSeconds: Double
        let captureDurationSeconds: Double
    }

    private struct Report: Codable {
        let method: String
        let reducedMotion: Bool
        let requestedIntervalSeconds: Double
        let logicalWidth: Double
        let logicalHeight: Double
        let frames: [Frame]
    }

    let host: NSView
    let output: URL
    let reducedMotion: Bool
    private let start = ContinuousClock.now
    private var frames: [Frame] = []

    init(host: NSView, output: URL, reducedMotion: Bool) throws {
        self.host = host
        self.output = output
        self.reducedMotion = reducedMotion
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    }

    func sample(_ beat: String, count: Int) async throws {
        for _ in 0..<count {
            try capture(beat)
            try await Task.sleep(for: .milliseconds(16))
        }
    }

    func capture(_ beat: String) throws {
        let instant = ContinuousClock.now
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let file = String(format: "%03d-%@.png", frames.count, beat)
        try png.write(to: output.appendingPathComponent(file))
        frames.append(Frame(file: file, beat: beat,
                            monotonicSeconds: start.duration(to: instant) / .seconds(1),
                            captureDurationSeconds: instant.duration(to: .now) / .seconds(1)))
    }

    func writeReport() throws {
        let report = Report(method: "Offscreen NSHostingView snapshots over mock state; requested waits exclude capture cost. Not a hardware recording or frame-rate measurement.",
                            reducedMotion: reducedMotion, requestedIntervalSeconds: 0.016,
                            logicalWidth: host.bounds.width, logicalHeight: host.bounds.height,
                            frames: frames)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: output.appendingPathComponent("rehearsal.json"))
    }
}
