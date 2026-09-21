import Foundation
import XCTest
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
@testable import NotchiumMediaFeature

@MainActor
final class TestAudioCapture: SystemAudioCapturing {
    private(set) var starts = 0
    private(set) var stops = 0
    var levels: (@Sendable ([CGFloat]) -> Void)?
    var failure: (@Sendable () -> Void)?
    var holdStop = false
    private var stopContinuation: CheckedContinuation<Void, Never>?
    func start(levels: @escaping @Sendable ([CGFloat]) -> Void,
               failure: @escaping @Sendable () -> Void) async throws {
        starts += 1; self.levels = levels; self.failure = failure
    }
    func stop() async {
        stops += 1
        if holdStop { await withCheckedContinuation { stopContinuation = $0 } }
    }
    func finishStop() { stopContinuation?.resume(); stopContinuation = nil }
}

@MainActor
final class AudioMeterLifecycleTests: XCTestCase {
    private final class PermissionGate {
        var isGranted = false
    }

    private func drain() async { for _ in 0..<30 { await Task.yield() } }
    private func state(_ playing: Bool) -> MediaState {
        .init(playbackState: playing ? .playing : .paused, title: "Track", trackID: "1", source: .spotify)
    }
    func testPermissionGrantDuringContinuousPlaybackStartsExistingMeter() async {
        let capture = TestAudioCapture()
        let permission = PermissionGate()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { permission.isGranted })
        meter.setPlaying(true); await drain()
        XCTAssertEqual(meter.status, .permissionRequired)
        XCTAssertEqual(capture.starts, 0)
        permission.isGranted = true
        meter.requestPermission(); await drain()
        XCTAssertTrue(meter.isRunning)
        XCTAssertEqual(capture.starts, 1)
        capture.levels?([0.2, 0.4, 0.6, 0.8, 1, 0.5, 0.3]); await drain()
        XCTAssertNotEqual(meter.waveformLevels, SystemAudioMeter.staticLevels)
        meter.setPlaying(true); await drain()
        XCTAssertEqual(capture.starts, 1)
        meter.stop(); await drain()
    }

    func testPauseImmediatelyGatesSamplesButKeepsActivityMonitorWarm() async {
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true })
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let model = MediaSessionController(provider: MockMediaProvider(), coordinator: ActivityCoordinator(clock: clock),
                                           visibilityClock: clock, audioMeter: meter)
        model.receive(state(true)); await drain()
        capture.levels?(Array(repeating: 0.8, count: 7)); await drain()
        XCTAssertEqual(meter.waveformLevels, Array(repeating: 0.8, count: 7))
        model.receive(state(false))
        XCTAssertEqual(meter.waveformLevels, SystemAudioMeter.staticLevels)
        capture.levels?(Array(repeating: 0.9, count: 7)); await drain()
        XCTAssertEqual(meter.waveformLevels, SystemAudioMeter.staticLevels)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(449)); await drain()
        XCTAssertTrue(model.collapsedMediaVisible)
        XCTAssertEqual(capture.starts, 1); XCTAssertEqual(capture.stops, 0)
        await clock.advance(by: .milliseconds(1)); await drain()
        XCTAssertFalse(model.collapsedMediaVisible)
        XCTAssertEqual(capture.stops, 0)
        XCTAssertTrue(model.state.hasMedia)
        XCTAssertEqual(meter.status, .capturing)
        model.stop()
        await drain()
        XCTAssertEqual(capture.stops, 1)
    }
    func testResumeBeforeHideReusesCaptureAndCancelsHide() async {
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true })
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let model = MediaSessionController(provider: MockMediaProvider(), coordinator: ActivityCoordinator(clock: clock),
                                           visibilityClock: clock, audioMeter: meter)
        model.receive(state(true)); await drain()
        model.receive(state(false)); await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(449))
        model.receive(state(true)); await clock.advance(by: .seconds(1)); await drain()
        capture.levels?(Array(repeating: 0.7, count: 7)); await drain()
        XCTAssertEqual(meter.waveformLevels, Array(repeating: 0.7, count: 7))
        XCTAssertTrue(model.collapsedMediaVisible)
        XCTAssertEqual(capture.starts, 1); XCTAssertEqual(capture.stops, 0)
        model.receive(.init(connectionState: .unauthenticated)); await drain()
        XCTAssertEqual(capture.stops, 1)
        model.stop()
    }
    func testResumeDuringStopSerializesCaptureAndRejectsOldCallbacks() async {
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true })
        meter.setPlaying(true); await drain()
        let staleOutput = capture.levels
        capture.holdStop = true
        meter.stop(); await drain()
        XCTAssertEqual(capture.stops, 1)
        meter.setPlaying(true); await drain()
        XCTAssertEqual(capture.starts, 1)
        capture.finishStop(); await drain()
        XCTAssertEqual(capture.starts, 2)
        staleOutput?(Array(repeating: 1, count: 7)); await drain()
        XCTAssertEqual(meter.waveformLevels, SystemAudioMeter.staticLevels)
        capture.levels?(Array(repeating: 0.6, count: 7)); await drain()
        XCTAssertEqual(meter.waveformLevels, Array(repeating: 0.6, count: 7))
        capture.holdStop = false; meter.stop(); await drain()
    }
    func testCaptureFailureStaysStaticWithoutPollDrivenRestart() async {
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true })
        meter.setPlaying(true); await drain()
        capture.failure?(); await drain()
        for _ in 0..<10 { meter.setPlaying(true); await drain() }
        XCTAssertEqual(meter.status, .unavailable)
        XCTAssertEqual(meter.waveformLevels, SystemAudioMeter.staticLevels)
        XCTAssertEqual(capture.starts, 1)
        meter.setPlaying(false); meter.setPlaying(true); await drain()
        XCTAssertEqual(capture.starts, 2)
        meter.stop(); await drain()
    }

    func testNonSilentSpotifyActivityRefreshesInactivePlaybackWithCooldown() async {
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true })
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let provider = MockMediaProvider()
        let model = MediaSessionController(provider: provider, coordinator: ActivityCoordinator(clock: clock),
                                           visibilityClock: clock, audioMeter: meter)
        model.receive(.init(connectionState: .authenticated, source: .spotify))
        await drain()
        XCTAssertEqual(capture.starts, 1)

        capture.levels?(Array(repeating: 0.8, count: 7))
        await drain()
        var refreshCount = await provider.refreshCount
        XCTAssertEqual(refreshCount, 1)
        capture.levels?(Array(repeating: 0.9, count: 7))
        await drain()
        refreshCount = await provider.refreshCount
        XCTAssertEqual(refreshCount, 1)

        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(2))
        await drain()
        capture.levels?(Array(repeating: 0.8, count: 7))
        await drain()
        refreshCount = await provider.refreshCount
        XCTAssertEqual(refreshCount, 2)
        model.stop()
    }
}
