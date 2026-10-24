import AppKit
import XCTest
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
@testable import NotchiumMediaFeature

@MainActor final class AudioMeterPermissionRecoveryTests: XCTestCase {
    func testGrantWhileSpotifyKeepsPlayingRecoversOnAppActivation() async {
        let capture = PermissionRecoveryCapture()
        capture.startError = .permissionDenied
        let notifications = NotificationCenter()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true },
                                     notificationCenter: notifications)
        let model = MediaSessionController(provider: MockMediaProvider(),
            coordinator: ActivityCoordinator(clock: ContinuousAppClock()), audioMeter: meter)
        defer { model.stop() }
        let playing = MediaState(playbackState: .playing, title: "Track", trackID: "1", source: .spotify)
        model.receive(playing)
        await drain()
        XCTAssertEqual(meter.status, .permissionRequired)
        XCTAssertFalse(model.collapsedMediaVisible)

        // Core Audio now accepts the user's grant, without a new playback transition.
        capture.startError = nil
        for _ in 0..<10 { model.receive(playing) }
        await drain()
        XCTAssertEqual(capture.starts, 1, "Metadata polling must not retry native permission requests")
        activate(using: notifications)
        await drain()
        XCTAssertEqual(capture.starts, 2)
        XCTAssertEqual(meter.status, .capturing)
        capture.levels?(Array(repeating: 0.7, count: 7))
        await drain()
        XCTAssertEqual(meter.waveformLevels, Array(repeating: 0.7, count: 7))
        XCTAssertTrue(meter.isAudioActive)
        XCTAssertTrue(model.collapsedMediaVisible)
    }

    func testGrantRecoversWhenAnotherAppBecomesActive() async {
        let capture = PermissionRecoveryCapture()
        capture.startError = .permissionDenied
        let workspaceNotifications = NotificationCenter()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true },
                                     workspaceNotificationCenter: workspaceNotifications)
        defer { meter.stop() }
        meter.setPlaying(true)
        await drain()
        XCTAssertEqual(capture.starts, 1)
        XCTAssertEqual(meter.status, .permissionRequired)

        // Menu-bar apps can remain inactive when the user leaves System Settings
        // and returns directly to Spotify after granting recording access.
        capture.startError = nil
        workspaceNotifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await drain()
        XCTAssertEqual(capture.starts, 2)
        XCTAssertEqual(meter.status, .capturing)
        capture.levels?(Array(repeating: 0.8, count: 7))
        await drain()
        XCTAssertTrue(meter.isAudioActive)
        XCTAssertEqual(meter.waveformLevels, Array(repeating: 0.8, count: 7))
    }

    func testActivationDuringPendingPermissionAttemptRecoversAfterItFails() async {
        let capture = PermissionRecoveryCapture()
        capture.startError = .permissionDenied
        capture.holdStart = true
        let notifications = NotificationCenter()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true },
                                     notificationCenter: notifications)
        defer { meter.stop() }
        meter.setPlaying(true)
        await drain()
        XCTAssertEqual(capture.starts, 1)
        XCTAssertEqual(meter.status, .starting)

        // The app can become active as the permission dialog closes, before the
        // first native attempt reports its result to the meter.
        capture.startError = nil
        activate(using: notifications)
        await drain()
        XCTAssertEqual(capture.starts, 1, "Recovery must wait for the existing native attempt")
        capture.finishStart()
        await drain()

        XCTAssertEqual(capture.starts, 2)
        XCTAssertEqual(capture.stops, 1, "The failed attempt is cleaned up before retrying")
        XCTAssertEqual(meter.status, .capturing)
    }

    func testRepeatedActivationsCoalesceWhileRecoveryStartIsPending() async {
        let capture = PermissionRecoveryCapture()
        capture.startError = .permissionDenied
        let notifications = NotificationCenter()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true },
                                     notificationCenter: notifications)
        defer { meter.stop() }
        meter.setPlaying(true)
        await drain()
        XCTAssertEqual(meter.status, .permissionRequired)

        capture.startError = nil
        capture.holdStart = true
        activate(using: notifications)
        await drain()
        XCTAssertEqual(capture.starts, 2)
        XCTAssertEqual(meter.status, .starting)
        for _ in 0..<10 { activate(using: notifications) }
        await drain()
        XCTAssertEqual(capture.starts, 2)

        capture.finishStart()
        await drain()
        XCTAssertEqual(capture.starts, 2, "One healthy retry satisfies every pending activation")
        XCTAssertEqual(meter.status, .capturing)
    }

    func testActivationsDoNotRestartHealthyCaptureOrStoppedMeter() async {
        let capture = PermissionRecoveryCapture()
        let notifications = NotificationCenter()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true },
                                     notificationCenter: notifications)
        meter.setPlaying(true)
        await drain()
        XCTAssertEqual(meter.status, .capturing)

        for _ in 0..<10 { activate(using: notifications) }
        await drain()
        XCTAssertEqual(capture.starts, 1)
        XCTAssertEqual(capture.stops, 0)

        meter.stop()
        await drain()
        for _ in 0..<10 { activate(using: notifications) }
        await drain()
        XCTAssertEqual(capture.starts, 1)
        XCTAssertEqual(capture.stops, 1)
        XCTAssertEqual(meter.status, .idle)
    }

    func testStoppedPermissionFailureDoesNotRecoverOnActivation() async {
        let capture = PermissionRecoveryCapture()
        capture.startError = .permissionDenied
        let notifications = NotificationCenter()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true },
                                     notificationCenter: notifications)
        meter.setPlaying(true)
        await drain()
        XCTAssertEqual(meter.status, .permissionRequired)

        meter.stop()
        await drain()
        capture.startError = nil
        activate(using: notifications)
        await drain()
        XCTAssertEqual(capture.starts, 1)
        XCTAssertFalse(meter.isRunning)
    }

    func testStopCancelsRecoveryWaitingForPendingStart() async {
        let capture = PermissionRecoveryCapture()
        capture.startError = .permissionDenied
        capture.holdStart = true
        let notifications = NotificationCenter()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true },
                                     notificationCenter: notifications)
        meter.setPlaying(true)
        await drain()
        XCTAssertEqual(meter.status, .starting)

        capture.startError = nil
        activate(using: notifications)
        await drain()
        meter.stop()
        capture.finishStart()
        await drain()

        XCTAssertEqual(capture.starts, 1, "A queued recovery must not revive a stopped meter")
        XCTAssertEqual(capture.stops, 1)
        XCTAssertFalse(meter.isRunning)
        XCTAssertFalse(meter.isAudioActive)
    }

    func testUnavailableCaptureCallbackRecoversOnActivation() async {
        let capture = PermissionRecoveryCapture()
        let notifications = NotificationCenter()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true },
                                     notificationCenter: notifications)
        defer { meter.stop() }
        meter.setPlaying(true)
        await drain()
        capture.levels?(Array(repeating: 0.7, count: 7))
        await drain()
        XCTAssertTrue(meter.isAudioActive)

        capture.failure?()
        await drain()
        XCTAssertEqual(meter.status, .unavailable)
        XCTAssertEqual(capture.stops, 1)
        XCTAssertFalse(meter.isAudioActive)
        XCTAssertEqual(meter.waveformLevels, SystemAudioMeter.staticLevels)

        activate(using: notifications)
        await drain()
        XCTAssertEqual(capture.starts, 2)
        XCTAssertEqual(meter.status, .capturing)
        capture.levels?(Array(repeating: 0.8, count: 7))
        await drain()
        XCTAssertTrue(meter.isAudioActive)
        XCTAssertEqual(meter.waveformLevels, Array(repeating: 0.8, count: 7))
    }

    private func activate(using notifications: NotificationCenter) {
        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    private func drain() async {
        for _ in 0..<100 { await Task.yield() }
    }
}

@MainActor private final class PermissionRecoveryCapture: SystemAudioCapturing {
    var starts = 0
    var stops = 0
    var startError: SystemAudioCaptureError?
    var holdStart = false
    var levels: (@Sendable ([CGFloat]) -> Void)?
    var failure: (@Sendable () -> Void)?
    private var startContinuation: CheckedContinuation<Void, Never>?

    func start(levels: @escaping @Sendable ([CGFloat]) -> Void,
               failure: @escaping @Sendable () -> Void) async throws {
        starts += 1
        let error = startError
        if holdStart {
            await withCheckedContinuation { startContinuation = $0 }
        }
        if let error { throw error }
        self.levels = levels
        self.failure = failure
    }

    func stop() async { stops += 1 }

    func finishStart() {
        holdStart = false
        startContinuation?.resume()
        startContinuation = nil
    }
}
