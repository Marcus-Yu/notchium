import Foundation
import XCTest
import NotchiumCore
@testable import NotchiumServices
@testable import NotchiumMediaFeature
@testable import NotchiumDynamicIsland

private actor HeldControlProvider: MediaProviding {
    var commands: [MediaCommand] = []
    var refreshCount = 0
    var held: [String: CheckedContinuation<Void, any Error>] = [:]
    var queueRefreshCount = 0
    func availability() -> FeatureAvailability { .available }
    func updates() -> AsyncStream<MediaState> { AsyncStream { $0.finish() } }
    func perform(_ command: MediaCommand) async throws {
        commands.append(command)
        try await withCheckedThrowingContinuation { held[command.controlID] = $0 }
    }
    func refresh() async { refreshCount += 1 }
    func loadQueue() async throws { queueRefreshCount += 1 }
    func finish(_ command: MediaCommand, failing: Bool = false) {
        let continuation = held.removeValue(forKey: command.controlID)
        if failing { continuation?.resume(throwing: MediaFailure.disconnected) }
        else { continuation?.resume() }
    }
    func waitFor(_ count: Int) async {
        while commands.count < count { await Task.yield() }
    }
    func waitForQueueRefresh(_ count: Int) async {
        while queueRefreshCount < count { await Task.yield() }
    }
}

@MainActor final class MediaControlTests: XCTestCase {
    private func model(_ provider: any MediaProviding, playing: Bool = false, elapsed: Double = 0,
                       timestamp: Date = Date()) -> MediaFeatureModel {
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(
            clock: TestAppClock(now: Date(), automaticallyAdvances: false)))
        model.receive(.init(playbackState: playing ? .playing : .paused, title: "Fixture", elapsed: elapsed, duration: 240,
                            capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true,
                                                canSeek: true, canShuffle: true, canRepeat: true),
                            shuffle: false, repeatMode: .off, timestamp: timestamp))
        return model
    }
    func testActualPlayPauseIntentAndIndependentDoubleTapProtection() async {
        for playing in [false, true] {
            let provider = HeldControlProvider()
            let model = model(provider, playing: playing)
            model.send(.next); model.send(.next)
            model.send(.playPause); model.send(.playPause)
            await provider.waitFor(2)
            let commands = await provider.commands
            XCTAssertEqual(commands.filter { $0 == .next }.count, 1)
            XCTAssertEqual(commands.filter { $0 == (playing ? .pause : .play) }.count, 1)
            XCTAssertEqual(model.state.isPlaying, playing)
            XCTAssertTrue(model.isPending(.next))
            XCTAssertTrue(model.isPending(.playPause))
            await provider.finish(.next)
            await provider.finish(.playPause)
            while model.isBusy { await Task.yield() }
            model.stop()
        }
    }
    func testFailureRefreshesAndClearsOnlyFailedControl() async {
        let provider = HeldControlProvider()
        let model = model(provider)
        let original = model.state
        model.send(.previous)
        let seek = Task { try await model.seek(to: 120) }
        await provider.waitFor(2)
        let commands = await provider.commands
        XCTAssertTrue(commands.contains(.seek(120)))
        await provider.finish(.previous, failing: true)
        while model.isPending(.previous) { await Task.yield() }
        XCTAssertTrue(model.isPending(.seek(0)))
        XCTAssertEqual(model.state, original)
        let refreshes = await provider.refreshCount
        XCTAssertEqual(refreshes, 1)
        await provider.finish(.seek(0), failing: true)
        do { try await seek.value; XCTFail("Failed seek succeeded") } catch {}
        while model.isBusy { await Task.yield() }
        XCTAssertNil(model.pendingSeek)
        model.stop()
    }
    func testNextAndPreviousRefreshQueueAfterSuccess() async {
        for command: MediaCommand in [.next, .previous] {
            let provider = HeldControlProvider()
            let model = model(provider, elapsed: command == .previous ? 0 : 20)
            model.send(command)
            await provider.waitFor(1)
            await provider.finish(command)
            while model.isBusy { await Task.yield() }
            let queueRefreshCount = await provider.queueRefreshCount
            XCTAssertEqual(queueRefreshCount, 1)
            model.stop()
        }
    }
    func testSpotifyTrackChangeRefreshesQueueOnce() async {
        let provider = HeldControlProvider()
        let model = model(provider)
        model.receive(.init(playbackState: .playing, title: "New Track", artist: "Artist",
                            elapsed: 0, duration: 240, trackID: "new", source: .spotify,
                            capabilities: .init(canPlayPause: true, canReadQueue: true)))
        await provider.waitForQueueRefresh(1)
        let queueRefreshCount = await provider.queueRefreshCount
        XCTAssertEqual(queueRefreshCount, 1)
        model.stop()
    }
    func testQueueFailureDoesNotBreakPlaybackState() async {
        let snapshot = MediaState(playbackState: .playing, title: "Fixture", artist: "Artist",
                                  elapsed: 10, duration: 240, trackID: "fixture", source: .spotify,
                                  capabilities: .init(canPlayPause: true, canReadQueue: true))
        let provider = MockMediaProvider(snapshot: snapshot, queueFailure: .invalidResponse)
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(
            clock: TestAppClock(now: Date(), automaticallyAdvances: false)))
        model.receive(snapshot)
        await model.loadQueue()
        let failedQueueState = await provider.snapshot
        model.receive(failedQueueState)
        XCTAssertTrue(model.state.hasMedia)
        XCTAssertTrue(model.state.canPlayPause)
        XCTAssertTrue(model.state.queue.isEmpty)
        XCTAssertEqual(model.state.queueIssue, "Unavailable")
        XCTAssertNil(model.errorMessage)
        model.stop()
    }
    func testMockEmptyQueueAndAddToQueueRefresh() async throws {
        let snapshot = MediaState(playbackState: .playing, title: "Fixture", artist: "Artist",
                                  duration: 240, trackID: "fixture", source: .spotify,
                                  capabilities: .init(canReadQueue: true), queue: [])
        let provider = MockMediaProvider(snapshot: snapshot)
        let initialQueue = await provider.snapshot.queue
        XCTAssertTrue(initialQueue.isEmpty)
        try await provider.addToQueue(uri: "spotify:track:awake")
        let queuedURIs = await provider.queuedURIs
        let queueRefreshCount = await provider.queueRefreshCount
        XCTAssertEqual(queuedURIs, ["spotify:track:awake"])
        XCTAssertEqual(queueRefreshCount, 1)
    }
    func testMockNextRemovesNewCurrentTrackFromQueueHead() async throws {
        let provider = MockMediaProvider()
        try await provider.apply(.play)
        try await provider.loadQueue()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(
            clock: TestAppClock(now: Date(), automaticallyAdvances: false)))
        model.start()
        while model.state.trackID == nil { await Task.yield() }
        model.send(.next)
        while model.isBusy || model.state.trackID == "midnight" { await Task.yield() }
        let state = await provider.snapshot
        XCTAssertEqual(state.trackID, "awake")
        XCTAssertEqual(state.queue.first?.id, "intro")
        XCTAssertNotEqual(state.queue.first?.id, state.trackID)
        model.stop()
    }
    func testPreviousRestartsThenMovesToPreviousTrack() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let provider = HeldControlProvider()
        let model = model(provider, elapsed: 90, timestamp: now)

        model.send(.previous)
        await provider.waitFor(1)
        var commands = await provider.commands
        XCTAssertEqual(commands, [.seek(0)])
        XCTAssertTrue(model.isPreviousPending)
        await provider.finish(.seek(0))
        while model.isBusy { await Task.yield() }

        model.receive(.init(playbackState: .paused, title: "Fixture", elapsed: 0, duration: 240,
                            capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true,
                                                canSeek: true, canShuffle: true, canRepeat: true),
                            shuffle: false, repeatMode: .off, timestamp: now))
        model.send(.previous)
        await provider.waitFor(2)
        commands = await provider.commands
        XCTAssertEqual(commands, [.seek(0), .previous])
        await provider.finish(.previous)
        while model.isBusy { await Task.yield() }
        model.stop()
    }
    func testPreviousUsesThreeSecondThresholdAndInterpolatedPosition() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let cases: [(playing: Bool, elapsed: Double, offset: TimeInterval, expected: MediaCommand)] = [
            (false, 1, 0, .previous),
            (false, 3, 0, .previous),
            (false, 3.01, 0, .seek(0)),
            (true, 1.5, 1.6, .seek(0)),
        ]
        for (playing, elapsed, offset, expected) in cases {
            let provider = HeldControlProvider()
            let model = model(provider, playing: playing, elapsed: elapsed, timestamp: now)
            model.previous(at: now.addingTimeInterval(offset))
            await provider.waitFor(1)
            let commands = await provider.commands
            XCTAssertEqual(commands, [expected])
            await provider.finish(expected)
            while model.isBusy { await Task.yield() }
            model.stop()
        }
    }
    func testMockExplicitCommandsAndModes() async throws {
        let provider = MockMediaProvider()
        try await provider.apply(.play)
        try await provider.pause()
        var state = await provider.snapshot
        XCTAssertFalse(state.isPlaying)
        try await provider.play()
        state = await provider.snapshot
        XCTAssertTrue(state.isPlaying)
        let first = state.trackID
        try await provider.nextTrack()
        state = await provider.snapshot
        XCTAssertNotEqual(state.trackID, first)
        XCTAssertEqual(state.elapsed, 0)
        try await provider.previousTrack()
        state = await provider.snapshot
        XCTAssertEqual(state.trackID, first)
        try await provider.seek(to: 120)
        state = await provider.snapshot
        XCTAssertEqual(state.elapsed, 120)
        for enabled in [true, false] {
            try await provider.setShuffle(enabled)
            state = await provider.snapshot
            XCTAssertEqual(state.shuffle, enabled)
        }
        for mode: MediaRepeatMode in [.context, .track, .off] {
            try await provider.setRepeatMode(mode)
            state = await provider.snapshot
            XCTAssertEqual(state.repeatMode, mode)
        }
    }
}
