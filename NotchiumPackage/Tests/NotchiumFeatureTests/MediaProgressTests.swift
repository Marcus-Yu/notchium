import Foundation
import XCTest
import NotchiumCore
@testable import NotchiumServices
@testable import NotchiumMediaFeature
@testable import NotchiumDynamicIsland

private actor HeldSeekProvider: MediaProviding {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func availability() -> FeatureAvailability { .available }
    func updates() -> AsyncStream<MediaState> { AsyncStream { $0.finish() } }
    func perform(_ command: MediaCommand) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            waiters.forEach { $0.resume() }; waiters.removeAll()
        }
    }
    func waitForSeek() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func finish(failing: Bool = false) {
        if failing { continuation?.resume(throwing: MediaFailure.unsupported) }
        else { continuation?.resume() }
        continuation = nil
    }
}

@MainActor final class MediaProgressTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private func sample(playing: Bool = true, rate: Double = 1, elapsed: Double = 30) -> MediaState {
        .init(playbackState: playing ? .playing : .paused, title: "Track", artist: "Artist",
              elapsed: elapsed, duration: 180, trackID: "1", source: .spotify,
              capabilities: .init(canSeek: true), timestamp: now, playbackRate: rate)
    }
    func testPlayingInterpolatesFromObservation() {
        XCTAssertEqual(estimatedPlaybackPosition(at: now.addingTimeInterval(10), state: sample()), 40)
    }
    func testPausedFreezesAndResumeRebases() {
        XCTAssertEqual(estimatedPlaybackPosition(at: now.addingTimeInterval(10), state: sample(playing: false)), 30)
        var resumed = sample(elapsed: 30)
        resumed.timestamp = now.addingTimeInterval(10)
        XCTAssertEqual(estimatedPlaybackPosition(at: now.addingTimeInterval(12), state: resumed), 32)
    }
    func testDoubleRate() {
        XCTAssertEqual(estimatedPlaybackPosition(at: now.addingTimeInterval(10), state: sample(rate: 2)), 50)
    }
    func testUpperClamp() {
        XCTAssertEqual(estimatedPlaybackPosition(at: now.addingTimeInterval(500), state: sample()), 180)
    }
    func testLowerClampAndInvalidValues() {
        XCTAssertEqual(estimatedPlaybackPosition(at: now.addingTimeInterval(-100), state: sample()), 0)
        XCTAssertEqual(estimatedPlaybackPosition(at: now, state: sample(elapsed: -30)), 0)
        for duration in [0.0, -10, Double.infinity, Double.nan] {
            var invalid = sample(); invalid.duration = duration
            XCTAssertEqual(estimatedPlaybackPosition(at: now, state: invalid), 0)
        }
        XCTAssertEqual(estimatedPlaybackPosition(at: now, state: sample(rate: .nan)), 30)
    }
    func testSeekHoldsThroughStaleSampleThenConfirms() async {
        let provider = HeldSeekProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(clock: TestAppClock(now: now, automaticallyAdvances: false)))
        model.receive(sample())
        model.seek(to: 90, at: now)
        await provider.waitForSeek()
        XCTAssertEqual(model.displayedPosition(at: now.addingTimeInterval(1)), 90)
        var stale = sample(elapsed: 31); stale.timestamp = now.addingTimeInterval(1)
        model.receive(stale)
        XCTAssertEqual(model.displayedPosition(at: now.addingTimeInterval(2)), 90)
        var confirmed = sample(elapsed: 92); confirmed.timestamp = now.addingTimeInterval(2)
        model.receive(confirmed)
        XCTAssertNil(model.pendingSeek)
        XCTAssertEqual(model.displayedPosition(at: now.addingTimeInterval(3)), 93)
        await provider.finish()
    }
    func testMetadataChangeImmediatelyResetsPendingSeek() async {
        // Test metadata changes even when the source reuses its ID.
        for field in ["title", "artist", "artwork", "trackID"] {
            let provider = HeldSeekProvider()
            let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(clock: TestAppClock(now: now, automaticallyAdvances: false)))
            model.receive(sample()); model.seek(to: 90, at: now)
            await provider.waitForSeek()
            var next = sample(elapsed: 2)
            switch field {
            case "title": next.title = "New track"
            case "artist": next.artist = "New artist"
            case "artwork": next.artwork = URL(string: "notchium-fixture://artwork/new")
            default: next.trackID = "2"
            }
            model.receive(next)
            XCTAssertNil(model.pendingSeek)
            XCTAssertEqual(model.displayedPosition(at: now), 2)
            await provider.finish()
        }
    }
    func testFailedSeekReleasesOptimisticPosition() async {
        let provider = HeldSeekProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(clock: TestAppClock(now: now, automaticallyAdvances: false)))
        model.receive(sample()); model.seek(to: 90, at: now)
        await provider.waitForSeek(); await provider.finish(failing: true)
        for _ in 0..<20 where model.isBusy { await Task.yield() }
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.pendingSeek)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.displayedPosition(at: now), 30)
    }
    func testCollapsedGeometryReservesHardwareAndNeverExtrudes() {
        let geometry = CollapsedMediaGeometry(hardwareWidth: 179, hardwareHeight: 32)
        XCTAssertEqual(geometry.height, 32)
        XCTAssertEqual(geometry.artworkSize, 20)
        XCTAssertEqual(geometry.width, 379)
        XCTAssertEqual(geometry.leadingWidth, geometry.trailingWidth)
        let passive = NotchShape(width: 179, height: 32, centerX: 320, topCornerRadius: 0, bottomCornerRadius: 8)
        let shape = NotchShellSurface(width: geometry.width, height: geometry.height,
                                      centerX: 320, bottomRadius: 8, passiveShape: passive)
        let bounds = shape.path(in: CGRect(x: 0, y: 0, width: 640, height: 210)).boundingRect
        XCTAssertEqual(bounds.minY, 0)
        XCTAssertEqual(bounds.maxY, 32)
        XCTAssertEqual(bounds.width, 379)
    }
}
