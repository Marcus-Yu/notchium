import Observation
import XCTest
@testable import NotchiumMediaFeature

@MainActor
final class AudioMeterObservationTests: XCTestCase {
    @MainActor
    private final class ChangeProbe {
        var changed = false
    }

    func testSamplesDoNotInvalidateStatusOrStableAudioActivityReaders() async throws {
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true })
        defer { meter.stop() }
        meter.setPlaying(true)
        await drain()
        capture.levels?(Array(repeating: 0.8, count: 7))
        await drain()
        XCTAssertEqual(meter.status, .capturing)
        XCTAssertTrue(meter.isAudioActive)

        let status = ChangeProbe()
        let activity = ChangeProbe()
        let waveform = ChangeProbe()
        withObservationTracking { _ = meter.status } onChange: {
            MainActor.assumeIsolated { status.changed = true }
        }
        withObservationTracking { _ = meter.isAudioActive } onChange: {
            MainActor.assumeIsolated { activity.changed = true }
        }
        withObservationTracking { _ = meter.waveformLevels } onChange: {
            MainActor.assumeIsolated { waveform.changed = true }
        }

        for value in [0.6, 0.9, 0.7] {
            capture.levels?(Array(repeating: value, count: 7))
            await drain()
        }
        XCTAssertTrue(waveform.changed)
        XCTAssertFalse(status.changed, "Settings must not update for each waveform sample")
        XCTAssertFalse(activity.changed, "Stable audio activity must not publish for each sample")

        capture.failure?()
        await drain()
        XCTAssertTrue(status.changed, "Status observers must still receive capture failure")
        XCTAssertTrue(activity.changed)
    }

    private func drain() async {
        for _ in 0..<30 { await Task.yield() }
    }
}
