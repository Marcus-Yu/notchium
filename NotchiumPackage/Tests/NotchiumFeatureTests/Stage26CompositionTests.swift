import XCTest
import NotchiumCore
import NotchiumFeature

@MainActor
final class Stage26CompositionTests: XCTestCase {
    func testMockCompositionNeverStartsARealSystemAudioTap() async {
        let controller = NotchiumApplicationController(environment: .mock(clock: ContinuousAppClock()))
        let meter = controller.mediaModel.audioMeter
        meter.setMonitoringPlaybackActivity(true)
        await waitUntil { meter.status != .idle }
        XCTAssertEqual(meter.status, .unavailable)
        XCTAssertFalse(meter.isRunning)
        meter.stop()
    }
}
