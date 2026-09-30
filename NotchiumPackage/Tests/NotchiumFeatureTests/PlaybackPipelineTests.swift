import Foundation
import XCTest
import NotchiumCore
@testable import NotchiumServices

@MainActor final class PlaybackPipelineTests: XCTestCase {
    private func state(id: String = "one", position: Double = 90, playing: Bool = true) -> MediaState {
        .init(playbackState: playing ? .playing : .paused, title: id, elapsed: position,
              duration: 240, trackID: id, source: .spotify)
    }

    func testLatePausedEventCannotReplaceSeekResumeExpectation() {
        let expectation = PlaybackReconciliation(origin: state(), target: .playingPosition(120), startedAt: 10)
        XCTAssertTrue(expectation.preservesSeek(through: .init(trackID: "one", isPlaying: false), uptime: 11))
        XCTAssertFalse(expectation.preservesSeek(through: .init(trackID: "two"), uptime: 11))
        XCTAssertFalse(expectation.preservesSeek(through: .init(isPlaying: false), uptime: 21))
    }

    func testDesktopHintCannotWeakenFinishedSeekExpectation() throws {
        let seek = try XCTUnwrap(PlaybackReconciliation(command: .seek(120), origin: state(), uptime: 10))
        XCTAssertTrue(seek.holdsPosition)
        XCTAssertTrue(seek.preservesSeek(through: .init(trackID: "one", isPlaying: true), uptime: 11))
        XCTAssertTrue(seek.preservesSeek(through: .init(trackID: "one", position: 121), uptime: 11))
        XCTAssertFalse(seek.preservesSeek(through: .init(trackID: "one", position: 40), uptime: 11),
                       "An external seek reported by Spotify Desktop replaces the command expectation")
        XCTAssertFalse(seek.preservesSeek(through: .init(trackID: "two"), uptime: 11))
        XCTAssertFalse(seek.preservesSeek(through: .init(trackID: "one"), uptime: 20))
        XCTAssertFalse(try XCTUnwrap(PlaybackReconciliation(command: .next, origin: state(), uptime: 10)).holdsPosition)
    }

    func testCommandExpectationsAreBoundedAndShareTheSameTrackRule() throws {
        for command: MediaCommand in [.next, .previous] {
            let expectation = try XCTUnwrap(PlaybackReconciliation(command: command, origin: state(), uptime: 100))
            XCTAssertFalse(expectation.accepts(state(), uptime: 100.1))
            XCTAssertTrue(expectation.accepts(state(id: "two", position: 0), uptime: 100.2))
            XCTAssertTrue(expectation.accepts(state(), uptime: 110))
        }
    }

    func testRestartAcceptsDelayedZeroButNotPreRestartProgress() throws {
        let expectation = try XCTUnwrap(PlaybackReconciliation(command: .seek(0), origin: state(), uptime: 100))
        XCTAssertFalse(expectation.accepts(state(position: 91), uptime: 101))
        XCTAssertTrue(expectation.accepts(state(position: 0), uptime: 104))
        XCTAssertTrue(expectation.accepts(state(position: 1), uptime: 105))
        XCTAssertTrue(expectation.accepts(state(id: "external", position: 40), uptime: 106))
        // Expiration depends on monotonic receipt time, including inactive/stale-dated samples.
        XCTAssertTrue(expectation.accepts(.init(timestamp: .distantPast), uptime: 110))
    }

    func testEventHintsUseSameSnapshotGateAndCannotPermanentlyBlockRemoteDevice() {
        let expectation = PlaybackReconciliation(origin: state(),
            target: .event(.init(trackID: "two", isPlaying: false, position: 0)), startedAt: 100)
        XCTAssertFalse(expectation.accepts(state(), uptime: 101))
        XCTAssertTrue(expectation.accepts(state(id: "two", position: 0, playing: false), uptime: 101))
        XCTAssertTrue(expectation.accepts(state(id: "remote", position: 70), uptime: 110))
    }

    func testNotificationAdapterOnlyObservesSpotifyAndParsesSafeHints() async {
        let center = NotificationCenter()
        let stream = SpotifyDesktopPlaybackEvents.observe(center: center)
        var iterator = stream.makeAsyncIterator()
        center.post(name: .init("unrelated.player"), object: nil,
                    userInfo: ["Track ID": "spotify:track:wrong"])
        center.post(name: .init("com.spotify.client.PlaybackStateChanged"), object: nil,
                    userInfo: ["Track ID": "spotify:track:two", "Player State": "Playing", "Playback Position": 1.5])
        let event = await iterator.next()
        XCTAssertEqual(event, .init(trackID: "two", isPlaying: true, position: 1.5))
        XCTAssertEqual(SpotifyPlaybackEvent(userInfo: ["Track ID": "other:track:one", "Playback Position": Double.nan]), .init())
    }
}
