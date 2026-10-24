import AppKit
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import SwiftUI
import XCTest
@testable import NotchiumMediaFeature

@MainActor
final class CollapsedMediaVisibilityTests: XCTestCase {
    private struct Session {
        let model: MediaSessionController
        let meter: SystemAudioMeter
        let capture: TestAudioCapture
        let audioClock: TestAppClock
        let visibilityClock: TestAppClock
        let coordinator: ActivityCoordinator
    }

    private func track() -> MediaState {
        .init(playbackState: .playing, title: "First track", duration: 180, trackID: "first",
              activeDeviceID: LocalSpotifyController.deviceID,
              activeDeviceName: "This Mac", activeDeviceType: "Computer",
              artwork: URL(string: "notchium-fixture://first"), source: .spotify,
              capabilities: .init(canPlayPause: true))
    }

    private func playingSession() async -> Session {
        let audioClock = TestAppClock(now: .now, automaticallyAdvances: false)
        let visibilityClock = TestAppClock(now: .now, automaticallyAdvances: false)
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true }, activityClock: audioClock)
        let coordinator = ActivityCoordinator(clock: visibilityClock)
        let model = MediaSessionController(provider: MockMediaProvider(snapshot: track()), coordinator: coordinator,
                                           visibilityClock: visibilityClock, audioMeter: meter)
        model.receive(track())
        await drain()
        capture.levels?(Array(repeating: 0.8, count: 7))
        await drain()
        await audioClock.waitForPendingSleeps()
        XCTAssertTrue(model.collapsedMediaVisible)
        return Session(model: model, meter: meter, capture: capture, audioClock: audioClock,
                       visibilityClock: visibilityClock, coordinator: coordinator)
    }

    private func becomeSilent(_ session: Session) async {
        session.capture.levels?(Array(repeating: AudioSpectrumAnalyzer.minimum, count: 7))
        await drain()
        await session.audioClock.advance(by: SystemAudioMeter.activityTimeout)
        await drain()
        await session.visibilityClock.waitForPendingSleeps()
        XCTAssertFalse(session.meter.isAudioActive)
        XCTAssertTrue(session.model.collapsedMediaVisible)
    }

    func testSilentTrackGapKeepsArtworkAndStaticWaveformUntilFixedDeadline() async throws {
        let session = await playingSession()
        defer { session.model.stop() }
        let activityID = try XCTUnwrap(session.coordinator.primary?.id)
        await becomeSilent(session)
        XCTAssertEqual(session.meter.waveformLevels, SystemAudioMeter.staticLevels)
        XCTAssertEqual(session.model.state.artwork, track().artwork)
        XCTAssertEqual(session.coordinator.primary?.minimal, .artwork)

        let renderer = ImageRenderer(content: CollapsedMediaWaveform(model: session.model)
            .environment(\.notchReduceMotionOverride, false)
            .environment(\.notchMediaExpanded, false).frame(width: 80, height: 40))
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        XCTAssertTrue((0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 }
        }, "Silence retains the real meter's static bars without invented audio samples")

        await session.visibilityClock.advance(by: .milliseconds(3_499))
        await drain()
        session.model.receive(track())
        XCTAssertTrue(session.model.collapsedMediaVisible)
        await session.visibilityClock.advance(by: .milliseconds(1))
        await drain()
        XCTAssertFalse(session.model.collapsedMediaVisible, "Repeated metadata cannot restart the silent deadline")
        XCTAssertNil(session.coordinator.primary?.minimal)
        XCTAssertEqual(session.coordinator.primary?.id, activityID)
        XCTAssertTrue(session.model.state.isPlaying, "Presentation grace never changes provider playback truth")
    }

    func testNextTrackAudioCancelsOldDeadlineAndCanStartANewSilentInterval() async {
        let session = await playingSession()
        defer { session.model.stop() }
        await becomeSilent(session)
        await session.visibilityClock.advance(by: .seconds(3))
        var next = track()
        next.trackID = "second"; next.title = "Second track"
        next.artwork = URL(string: "notchium-fixture://second")
        session.model.receive(next)
        session.capture.levels?(Array(repeating: 0.6, count: 7))
        await drain()
        await session.visibilityClock.advance(by: .seconds(2))
        await drain()
        XCTAssertTrue(session.model.collapsedMediaVisible)
        XCTAssertEqual(session.model.state.artwork, next.artwork)
        XCTAssertEqual(session.meter.waveformLevels, Array(repeating: 0.6, count: 7))

        await becomeSilent(session)
        await session.visibilityClock.advance(by: .milliseconds(3_500))
        await drain()
        XCTAssertFalse(session.model.collapsedMediaVisible)
    }

    func testPauseStoppedSourceLossAndUnavailablePlaybackCancelGraceImmediately() async {
        var paused = track(); paused.playbackState = .paused
        var stopped = track(); stopped.playbackState = .stopped
        var noSource = track(); noSource.source = nil
        var denied = track(); denied.availability = .unavailable(.permissionDenied)
        var disconnected = track(); disconnected.connectionState = .unauthenticated
        var failed = track(); failed.connectionState = .error
        var remote = track()
        remote.activeDeviceID = "phone"; remote.activeDeviceName = "Phone"; remote.activeDeviceType = "Smartphone"
        let lostSpotify = MediaState(source: .spotify, localSpotifyStatus: .notRunning)
        for invalid in [paused, stopped, noSource, denied, disconnected, failed, remote, lostSpotify] {
            let session = await playingSession()
            await becomeSilent(session)
            session.model.receive(invalid)
            XCTAssertFalse(session.model.collapsedMediaVisible, "\(invalid) must cancel a silent presentation immediately")
            await session.visibilityClock.advance(by: .seconds(5))
            await drain()
            XCTAssertFalse(session.model.collapsedMediaVisible)
            session.model.stop()
        }
    }

    func testPauseCommandAndCaptureFailureCancelGraceImmediately() async {
        for failCapture in [false, true] {
            let session = await playingSession()
            await becomeSilent(session)
            if failCapture { session.capture.failure?(); await drain() }
            else { session.model.send(.pause) }
            XCTAssertFalse(session.model.collapsedMediaVisible)
            await session.visibilityClock.advance(by: .seconds(5))
            await drain()
            XCTAssertFalse(session.model.collapsedMediaVisible)
            session.model.stop()
        }
    }

    func testNoAudioCannotStartGraceAndStopCannotBeUndoneByItsDeadline() async {
        let session = await playingSession()
        await becomeSilent(session)
        session.model.stop()
        await session.visibilityClock.advance(by: .seconds(5))
        await drain()
        XCTAssertFalse(session.model.collapsedMediaVisible)
        session.model.receive(track())
        await drain()
        XCTAssertFalse(session.model.collapsedMediaVisible, "A new playing snapshot still needs actual local audio")
        session.model.stop()
    }

    private func drain() async { for _ in 0..<50 { await Task.yield() } }
}
