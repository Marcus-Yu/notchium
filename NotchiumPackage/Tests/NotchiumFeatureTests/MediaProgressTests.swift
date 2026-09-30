import AppKit
import Foundation
import SwiftUI
import XCTest
import NotchiumCore
@testable import NotchiumServices
@testable import NotchiumMediaFeature
@testable import NotchiumDynamicIsland

private actor HeldSeekProvider: MediaProviding {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestedPositions: [Double] = []
    private(set) var refreshCount = 0
    private(set) var commands: [MediaCommand] = []
    func availability() -> FeatureAvailability { .available }
    func updates() -> AsyncStream<MediaState> { AsyncStream { $0.finish() } }
    func perform(_ command: MediaCommand) async throws {
        commands.append(command)
        guard case .seek(let position) = command else { return }
        requestedPositions.append(position)
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            waiters.forEach { $0.resume() }; waiters.removeAll()
        }
    }
    func refresh() async { refreshCount += 1 }
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
    func testSeekPreservesPlaybackStateAndKeepsManualHome() async throws {
        for playing in [false, true] {
            let provider = HeldSeekProvider()
            let presentation = DynamicIslandPresentationModel()
            let model = MediaFeatureModel(provider: provider, coordinator: presentation.activityCoordinator)
            var origin = sample(playing: playing, rate: playing ? 1 : 0)
            origin.capabilities.canPlayPause = true
            model.receive(origin)
            presentation.setExpanded(true)
            presentation.pageModel.selectedPage = .home
            let seek = Task { try await model.seek(to: 90, at: now) }
            await provider.waitForSeek()
            XCTAssertEqual(model.state.isPlaying, playing)
            XCTAssertEqual(model.lastSeekTarget, 90)
            XCTAssertFalse(model.isPending(.playPause))
            await provider.finish()
            try await seek.value
            let commands = await provider.commands
            XCTAssertEqual(commands, [.seek(90)], "a seek never sends Play (playing=\(playing))")
            XCTAssertEqual(model.state.isPlaying, playing)
            XCTAssertEqual(presentation.pageModel.selectedPage, .home)
            XCTAssertFalse(model.seekInFlight)
            model.stop()
            presentation.reset()
        }
    }

    func testPlayPressedDuringPausedSeekIsNotOverwritten() async throws {
        let provider = HeldSeekProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(clock: ContinuousAppClock()))
        var paused = sample(playing: false, rate: 0)
        paused.capabilities.canPlayPause = true
        model.receive(paused)
        let seek = Task { try await model.seek(to: 90, at: now) }
        await provider.waitForSeek()
        model.send(.play)
        for _ in 0..<50 where await provider.commands.count < 2 { await Task.yield() }
        XCTAssertTrue(model.state.isPlaying)
        await provider.finish()
        try await seek.value
        let commands = await provider.commands
        XCTAssertEqual(commands.filter { $0 == .play }.count, 1, "only the user's Play")
        XCTAssertTrue(model.state.isPlaying)
        model.stop()
    }

    func testFailedPausedSeekDoesNotResumeAndReleasesBothControls() async {
        let provider = HeldSeekProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(clock: ContinuousAppClock()))
        var paused = sample(playing: false)
        paused.capabilities.canPlayPause = true
        model.receive(paused)
        let seek = Task { try await model.seek(to: 90, at: now) }
        await provider.waitForSeek()
        await provider.finish(failing: true)
        do { try await seek.value; XCTFail("Expected failure") } catch {}
        let commands = await provider.commands
        XCTAssertEqual(commands, [.seek(90)])
        XCTAssertFalse(model.state.isPlaying)
        XCTAssertFalse(model.isBusy)
        model.stop()
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
    func testSeekRejectsBufferedPreActionSampleThenAcceptsSnapshot() async {
        let provider = HeldSeekProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(clock: TestAppClock(now: now, automaticallyAdvances: false)))
        model.receive(sample())
        let seek = Task { try await model.seek(to: 90, at: now) }
        await provider.waitForSeek()
        XCTAssertEqual(model.displayedPosition(at: now.addingTimeInterval(1)), 91)
        var stale = sample(elapsed: 31); stale.timestamp = now.addingTimeInterval(-1)
        model.receive(stale)
        XCTAssertEqual(model.displayedPosition(at: now.addingTimeInterval(2)), 92)
        var confirmed = sample(elapsed: 92); confirmed.timestamp = now.addingTimeInterval(2)
        model.receive(confirmed)
        XCTAssertNil(model.lastSeekTarget)
        XCTAssertEqual(model.displayedPosition(at: now.addingTimeInterval(3)), 93)
        await provider.finish()
        try? await seek.value
    }
    func testMetadataChangeImmediatelyResetsPendingSeek() async {
        // Test metadata changes even when the source reuses its ID.
        for field in ["title", "artist", "artwork", "trackID"] {
            let provider = HeldSeekProvider()
            let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(clock: TestAppClock(now: now, automaticallyAdvances: false)))
            model.receive(sample())
            let seek = Task { try await model.seek(to: 90, at: now) }
            await provider.waitForSeek()
            var next = sample(elapsed: 2)
            switch field {
            case "title": next.title = "New track"
            case "artist": next.artist = "New artist"
            case "artwork": next.artwork = URL(string: "notchium-fixture://artwork/new")
            default: next.trackID = "2"
            }
            model.receive(next)
            XCTAssertNil(model.lastSeekTarget)
            XCTAssertEqual(model.displayedPosition(at: now), 2)
            await provider.finish()
            try? await seek.value
        }
    }
    func testFailedSeekReleasesOptimisticPosition() async {
        let provider = HeldSeekProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(clock: TestAppClock(now: now, automaticallyAdvances: false)))
        model.receive(sample())
        let seek = Task { try await model.seek(to: 90, at: now) }
        await provider.waitForSeek(); await provider.finish(failing: true)
        do { try await seek.value; XCTFail("Failed seek succeeded") } catch {}
        for _ in 0..<20 where model.isBusy { await Task.yield() }
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.lastSeekTarget)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.displayedPosition(at: now), 30)
    }
    func testSeekCallsProviderOnceWithoutRedundantRefresh() async throws {
        let provider = HeldSeekProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(
            clock: TestAppClock(now: now, automaticallyAdvances: false)))
        model.receive(sample(elapsed: 120))
        let seek = Task { try await model.seek(to: 60, at: now) }
        await provider.waitForSeek()
        XCTAssertTrue(model.seekInFlight)
        XCTAssertEqual(model.lastSeekTarget, 60)
        let requestedPositions = await provider.requestedPositions
        XCTAssertEqual(requestedPositions, [60])
        await provider.finish()
        try await seek.value
        let refreshCount = await provider.refreshCount
        XCTAssertEqual(refreshCount, 0)
    }
    func testSeekDispatchPublishesOptimisticPositionSynchronously() async {
        let provider = HeldSeekProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(
            clock: TestAppClock(now: now, automaticallyAdvances: false)))
        model.receive(sample(elapsed: 30))

        model.send(.seek(90))
        XCTAssertEqual(model.lastSeekTarget, 90)
        XCTAssertEqual(model.displayedPosition(at: Date()), 90, accuracy: 0.1)

        await provider.waitForSeek()
        await provider.finish()
        while model.isBusy { await Task.yield() }
        model.stop()
    }
    func testRestartImmediatelyRebasesAndContinuesLocalClock() async {
        let provider = HeldSeekProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(
            clock: TestAppClock(now: now, automaticallyAdvances: false)))
        model.receive(sample(elapsed: 120))

        let seek = Task { try await model.seek(to: 0, at: now) }
        await provider.waitForSeek()
        XCTAssertEqual(model.state.elapsed, 0)
        XCTAssertEqual(model.state.timestamp, now)
        XCTAssertEqual(model.displayedPosition(at: now), 0)
        XCTAssertEqual(model.displayedPosition(at: now.addingTimeInterval(1.5)), 1.5)

        var stale = sample(elapsed: 122)
        stale.timestamp = now.addingTimeInterval(-1)
        model.receive(stale)
        XCTAssertEqual(model.state.elapsed, 0)
        XCTAssertEqual(model.state.timestamp, now)
        XCTAssertEqual(model.displayedPosition(at: now.addingTimeInterval(2)), 2)

        await provider.finish()
        try? await seek.value
        model.stop()
    }
    func testReadStartedBeforeRestartCannotReplaceItsNewClock() async {
        let provider = HeldSeekProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(
            clock: TestAppClock(now: now, automaticallyAdvances: false)))
        model.receive(sample(elapsed: 90))
        let seek = Task { try await model.seek(to: 0, at: now) }
        await provider.waitForSeek()
        let baseline = model.state.sampledUptime!
        var old = sample(elapsed: 91)
        old.observationStartedUptime = baseline - 1
        old.sampledUptime = baseline + 1
        old.timestamp = now.addingTimeInterval(1)
        model.receive(old)
        XCTAssertEqual(model.displayedPosition(at: now, uptime: baseline + 2), 2)
        var fresh = sample(elapsed: 1)
        fresh.observationStartedUptime = baseline + 2
        fresh.sampledUptime = baseline + 3
        fresh.timestamp = now.addingTimeInterval(3)
        model.receive(fresh)
        XCTAssertEqual(model.state, fresh)
        XCTAssertEqual(model.displayedPosition(at: now, uptime: baseline + 4), 2)
        await provider.finish()
        try? await seek.value
        model.stop()
    }

    func testSnapshotClockUsesMonotonicTimeAcrossWallClockChanges() {
        var snapshot = sample(elapsed: 90)
        snapshot.sampledUptime = 100
        XCTAssertEqual(estimatedPlaybackPosition(at: now.addingTimeInterval(3600), state: snapshot, uptime: 102), 92)
        snapshot.elapsed = 0
        snapshot.sampledUptime = 103
        XCTAssertEqual(estimatedPlaybackPosition(at: now.addingTimeInterval(-3600), state: snapshot, uptime: 104), 1)
    }

    func testTimelineDisplayKeepsSeekPositionWhileDragging() {
        XCTAssertEqual(mediaSliderDisplayPosition(isSeeking: true, seekPosition: 60,
                                                  estimatedPosition: 120), 60)
        XCTAssertEqual(mediaSliderDisplayPosition(isSeeking: false, seekPosition: 60,
                                                  estimatedPosition: 120), 120)
    }
    func testCollapsedVisibilityRequiresCurrentLocalSpotifyAudio() async {
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let coordinator = ActivityCoordinator(clock: clock)
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true }, activityClock: clock)
        let model = MediaFeatureModel(provider: MockMediaProvider(), coordinator: coordinator,
                                      visibilityClock: clock, audioMeter: meter)
        var local = sample()
        local.activeDeviceID = "mac"
        local.activeDeviceName = "This Mac"
        local.activeDeviceType = "Computer"
        model.receive(local)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertFalse(model.collapsedMediaVisible)

        capture.levels?(Array(repeating: 0.8, count: 7))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(model.collapsedMediaVisible)

        var paused = local
        paused.playbackState = .paused
        paused.playbackRate = 0
        model.receive(paused)
        XCTAssertFalse(model.collapsedMediaVisible)

        capture.levels?(Array(repeating: 0.8, count: 7))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertFalse(model.collapsedMediaVisible)

        var remote = local
        remote.activeDeviceID = "iphone"
        remote.activeDeviceName = "iPhone"
        remote.activeDeviceType = "Smartphone"
        model.receive(remote)
        XCTAssertFalse(model.collapsedMediaVisible)
        XCTAssertTrue(model.state.hasMedia)
        XCTAssertNotNil(coordinator.activeActivity)

        model.receive(.init())
        XCTAssertFalse(model.collapsedMediaVisible)
        XCTAssertNotNil(coordinator.activeActivity)
        XCTAssertTrue(model.isShowingCachedTrack)
        XCTAssertEqual(model.state.playbackState, .paused)
        model.stop()
    }
    func testCollapsedGeometryReservesHardwareAndNeverExtrudes() {
        let geometry = CollapsedMediaGeometry(hardwareWidth: 179, hardwareHeight: 32)
        XCTAssertEqual(geometry.height, 32)
        XCTAssertEqual(geometry.artworkSize, 24)
        XCTAssertEqual(geometry.width, 259)
        XCTAssertEqual(geometry.leadingWidth, geometry.trailingWidth)
        let passive = NotchShape(width: 179, height: 32, centerX: 320, topCornerRadius: 0, bottomCornerRadius: 8)
        let shape = NotchShellSurface(width: geometry.width, height: geometry.height,
                                      centerX: 320, bottomRadius: 8, passiveShape: passive)
        let bounds = shape.path(in: CGRect(x: 0, y: 0, width: 640, height: 210)).boundingRect
        XCTAssertEqual(bounds.minY, 0)
        XCTAssertEqual(bounds.maxY, 32)
        XCTAssertEqual(bounds.width, 259)
    }

    /// Real AppKit event routing (hit testing, first mouse, drag, release) through the hosted slider.
    func testPointerDragOnHostedSeekSliderSendsOneSeek() async throws {
        for playing in [true, false] {
            let snapshot = MediaState(playbackState: playing ? .playing : .paused, title: "Fixture",
                                      elapsed: 10, duration: 200, trackID: "t", source: .spotify,
                                      capabilities: .init(canPlayPause: true, canSeek: true),
                                      playbackRate: playing ? 1 : 0)
            let provider = MockMediaProvider(snapshot: snapshot)
            let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(
                clock: TestAppClock(now: Date(), automaticallyAdvances: false)))
            model.start()
            while !model.state.hasMedia { await Task.yield() }
            let panel = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 300, height: 60),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.contentView = NSHostingView(rootView: MediaProgressView(model: model).frame(width: 300, height: 60))
            panel.orderFrontRegardless()
            defer { panel.orderOut(nil) }
            panel.contentView?.layoutSubtreeIfNeeded()
            await drainMainActorTasks()
            let pointer = try XCTUnwrap(Self.view(named: "PointerView", in: panel.contentView))
            let frame = pointer.convert(pointer.bounds, to: nil)
            func post(_ type: NSEvent.EventType, _ fraction: CGFloat) async {
                let location = CGPoint(x: frame.minX + frame.width * fraction, y: frame.midY)
                panel.sendEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
                await drainMainActorTasks()
            }
            await post(.leftMouseDown, 0.2)
            await post(.leftMouseDragged, 0.5)
            await post(.leftMouseUp, 0.5)
            for _ in 0..<200 where await provider.commands.isEmpty { await Task.yield() }
            let commands = await provider.commands
            let seeks = commands.compactMap { if case .seek(let value) = $0 { value } else { nil } }
            XCTAssertEqual(seeks.count, 1, "playing=\(playing) commands=\(commands)")
            XCTAssertEqual(seeks.first ?? 0, 100, accuracy: 3, "playing=\(playing)")
            model.stop()
        }
    }

    private static func view(named name: String, in root: NSView?) -> NSView? {
        guard let root else { return nil }
        if String(describing: type(of: root)).contains(name) { return root }
        for child in root.subviews { if let found = view(named: name, in: child) { return found } }
        return nil
    }
}
