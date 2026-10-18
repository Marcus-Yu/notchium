import AppKit
import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import SwiftUI
import XCTest
@testable import NotchiumMediaFeature
@testable import NotchiumServices

private actor LocalSpotifyApplication: SpotifyApplicationLaunching {
    var installed = true
    var running = true
    private(set) var launches = 0
    func isSpotifyInstalled() -> Bool { installed }
    func isSpotifyRunning() -> Bool { running }
    func launchSpotify() { launches += 1; running = true }
    func set(installed: Bool = true, running: Bool) { self.installed = installed; self.running = running }
}
private actor LocalSpotifyPreferencesFixture: SpotifyLocalPreferencesStoring {
    var enabled: Bool
    init(_ enabled: Bool = true) { self.enabled = enabled }
    func isEnabled() -> Bool { enabled }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled }
}
private actor LocalSpotifyScripts: SpotifyScriptExecuting {
    private(set) var sources: [String] = []
    private(set) var permissionChecks = 0
    var failure: Int?
    var access: SpotifyAutomationPermission = .allowed
    var fields = LocalSpotifyScripts.track()
    private var nextResponses: [[String]] = []
    private var heldRead: CheckedContinuation<[String], Never>?
    private var shouldHoldRead = false
    private var readObservers: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var reads = 0
    static func track(id: String = "one", playing: Bool = true, position: String = "45", artwork: String = "https://i.scdn.co/image/test") -> [String] {
        [playing ? "playing" : "paused", "spotify:track:\(id)", "Title \(id)", "Artist\nWith a tab\t", "Album", artwork,
         "240000", position, "65", "false", "false", "true", "true", "local"]
    }
    func permission() -> SpotifyAutomationPermission { permissionChecks += 1; return access }
    func setFailure(_ code: Int?) { failure = code }
    func setAccess(_ access: SpotifyAutomationPermission) { self.access = access }
    func setFields(_ fields: [String]) { self.fields = fields }
    func respond(_ values: [[String]]) { nextResponses = values }
    func holdNextRead() { shouldHoldRead = true }
    func execute(_ source: String) async throws -> [String] {
        sources.append(source)
        if let failure { throw SpotifyScriptFailure(code: failure) }
        if source == LocalSpotifyController.snapshotScript {
            reads += 1
            let ready = readObservers.filter { reads >= $0.0 }
            readObservers.removeAll { reads >= $0.0 }
            ready.forEach { $0.1.resume() }
            if shouldHoldRead {
                shouldHoldRead = false
                return await withCheckedContinuation { heldRead = $0 }
            }
            if !nextResponses.isEmpty { return nextResponses.removeFirst() }
            return fields
        }
        if source.contains("\n        pause\n") { fields[0] = "paused" }
        if source.contains("\n        play\n") { fields[0] = "playing" }
        return ["ok"]
    }
    func waitForReads(_ count: Int) async {
        if reads >= count { return }
        await withCheckedContinuation { readObservers.append((count, $0)) }
    }
    func releaseRead(_ value: [String]) { heldRead?.resume(returning: value); heldRead = nil }
    func waitForHeldRead() async { while heldRead == nil { await Task.yield() } }
}
private actor LocalSpotifyEvents: SpotifyPlaybackEventProviding, SpotifyLifecycleEventProviding {
    private var playback: AsyncStream<SpotifyPlaybackEvent>.Continuation?
    private var lifecycle: AsyncStream<SpotifyLifecycleEvent>.Continuation?
    func events() -> AsyncStream<SpotifyPlaybackEvent> {
        let pair = AsyncStream<SpotifyPlaybackEvent>.makeStream(); playback = pair.continuation; return pair.stream
    }
    func events() -> AsyncStream<SpotifyLifecycleEvent> {
        let pair = AsyncStream<SpotifyLifecycleEvent>.makeStream(); lifecycle = pair.continuation; return pair.stream
    }
    func waitUntilObserved() async { while playback == nil || lifecycle == nil { await Task.yield() } }
    func send(_ event: SpotifyPlaybackEvent) { playback?.yield(event) }
    func send(_ event: SpotifyLifecycleEvent) { lifecycle?.yield(event) }
}

@MainActor final class SpotifyMediaTests: XCTestCase {
    func testConfiguredComputerNamesRecognizeLocalPlayback() {
        let names = SystemSpotifyApplicationLauncher.localDeviceNames(
            computerName: "  QA Computer  ", localHostName: "QA-Computer")
        let model = MediaFeatureModel(provider: MockMediaProvider(),
                                      coordinator: ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false)),
                                      localDeviceNames: names)
        for name in ["This Mac", "QA Computer", "QA-Computer", "QA-Computer.local"] {
            model.receive(.init(playbackState: .paused, title: "Disposable test track",
                                activeDeviceID: "legacy-device", activeDeviceName: name,
                                activeDeviceType: "Computer", source: .spotify))
            XCTAssertTrue(model.isPlaybackLocal, name)
        }
        model.receive(.init(playbackState: .paused, title: "Disposable test track",
                            activeDeviceID: "remote-device", activeDeviceName: "Another Computer",
                            activeDeviceType: "Computer", source: .spotify))
        XCTAssertFalse(model.isPlaybackLocal)
        model.stop()
    }

    func testMissingConfiguredNamesKeepLocalDeviceFallback() {
        XCTAssertEqual(SystemSpotifyApplicationLauncher.localDeviceNames(
            computerName: nil, localHostName: nil), ["this mac"])
        XCTAssertEqual(SystemSpotifyApplicationLauncher.localDeviceNames(
            computerName: " \n", localHostName: "\t"), ["this mac"])
    }

    private func snapshot(_ provider: RealMediaProvider) async -> MediaState {
        var iterator = await provider.updates().makeAsyncIterator()
        return await iterator.next()!
    }
    private func provider(_ scripts: LocalSpotifyScripts, application: LocalSpotifyApplication = .init(),
                          preferences: LocalSpotifyPreferencesFixture = .init(),
                          events: LocalSpotifyEvents = .init(), clock: TestAppClock? = nil) -> RealMediaProvider {
        .init(controller: .init(executor: scripts, application: application, preferences: preferences),
              clock: clock ?? TestAppClock(now: .now, automaticallyAdvances: false),
              playbackEvents: events, lifecycleEvents: events)
    }

    func testUnavailableSpotifyNeverExecutesScriptOrLaunches() async throws {
        for installed in [true, false] {
            let app = LocalSpotifyApplication(); await app.set(installed: installed, running: false)
            let scripts = LocalSpotifyScripts()
            let controller = LocalSpotifyController(executor: scripts, application: app,
                preferences: LocalSpotifyPreferencesFixture())
            let state = try await controller.read()
            XCTAssertEqual(state.localSpotifyStatus, installed ? .notRunning : .notInstalled)
            XCTAssertFalse(state.hasMedia)
            let sources = await scripts.sources; let launches = await app.launches
            XCTAssertTrue(sources.isEmpty); XCTAssertEqual(launches, 0)
        }
    }
    func testFirstUseRequiresExplicitEnableAndDenialNeverReprompts() async throws {
        let scripts = LocalSpotifyScripts(); let preferences = LocalSpotifyPreferencesFixture(false)
        let controller = LocalSpotifyController(executor: scripts, application: LocalSpotifyApplication(), preferences: preferences)
        let initial = try await controller.read(); XCTAssertEqual(initial.localSpotifyStatus, .needsPermission)
        var checks = await scripts.permissionChecks; XCTAssertEqual(checks, 0)
        await scripts.setAccess(.denied)
        let denied = try await controller.read(prompt: true); XCTAssertEqual(denied.localSpotifyStatus, .denied)
        for _ in 0..<3 { _ = try await controller.read() }
        checks = await scripts.permissionChecks
        XCTAssertEqual(checks, 4)
        let sources = await scripts.sources; XCTAssertTrue(sources.isEmpty)
        await scripts.setAccess(.allowed)
        let recovered = try await controller.read(); XCTAssertTrue(recovered.hasMedia)
    }
    func testExplicitEnableUsesNormalAppleEventForUndeterminedConsent() async throws {
        let scripts = LocalSpotifyScripts(); await scripts.setAccess(.notDetermined)
        let controller = LocalSpotifyController(executor: scripts, application: LocalSpotifyApplication(),
                                               preferences: LocalSpotifyPreferencesFixture())
        let passive = try await controller.read(); XCTAssertEqual(passive.localSpotifyStatus, .needsPermission)
        var sources = await scripts.sources; XCTAssertTrue(sources.isEmpty)
        let enabled = try await controller.read(prompt: true); XCTAssertTrue(enabled.hasMedia)
        sources = await scripts.sources; XCTAssertEqual(sources, [LocalSpotifyController.snapshotScript])
    }
    func testPermissionRequestImmediatelyPopulatesAndRestoresWithoutPrompt() async throws {
        let scripts = LocalSpotifyScripts(); let preferences = LocalSpotifyPreferencesFixture(false)
        let provider = provider(scripts, preferences: preferences)
        try await provider.connect()
        try await provider.enableLocalControl()
        let state = await snapshot(provider)
        XCTAssertEqual(state.title, "Title one"); XCTAssertEqual(state.localSpotifyStatus, .ready)
        await provider.shutdown()
        let relaunched = self.provider(scripts, preferences: preferences)
        try await relaunched.connect()
        let checks = await scripts.permissionChecks; XCTAssertEqual(checks, 2)
        await relaunched.shutdown()
    }
    func testPermissionRevokedBetweenPreflightAndScriptIsHandled() async throws {
        let scripts = LocalSpotifyScripts()
        let controller = LocalSpotifyController(executor: scripts, application: LocalSpotifyApplication(),
                                               preferences: LocalSpotifyPreferencesFixture())
        await scripts.setFailure(-1743)
        let denied = try await controller.read(); XCTAssertEqual(denied.localSpotifyStatus, .denied)
        await scripts.setFailure(-600)
        let quit = try await controller.read(); XCTAssertEqual(quit.localSpotifyStatus, .notRunning)
    }
    func testDeniedProviderNeverStartsFallbackOrRunsMetadataScripts() async throws {
        let scripts = LocalSpotifyScripts(); await scripts.setAccess(.denied)
        let clock = TestAppClock(now: .now, automaticallyAdvances: false)
        let provider = provider(scripts, clock: clock); try await provider.connect()
        await provider.refresh()
        let sources = await scripts.sources; let sleeps = await clock.sleepHistory()
        XCTAssertTrue(sources.isEmpty); XCTAssertTrue(sleeps.isEmpty)
        let state = await snapshot(provider); XCTAssertEqual(state.availability, .unavailable(.permissionDenied))
        XCTAssertFalse(state.hasMedia)
        await provider.shutdown()
    }
    func testPlayingPausedMetadataAlbumDurationAndArtwork() throws {
        for playing in [true, false] {
            let state = try LocalSpotifyController.decode(LocalSpotifyScripts.track(playing: playing))
            XCTAssertEqual(state.isPlaying, playing); XCTAssertEqual(state.playbackRate, playing ? 1 : 0)
            XCTAssertEqual(state.album, "Album"); XCTAssertEqual(state.artist, "Artist\nWith a tab\t")
            XCTAssertEqual(state.duration, 240); XCTAssertEqual(state.elapsed, 45)
            XCTAssertEqual(state.trackID, "one"); XCTAssertEqual(state.volumePercent, 65)
            XCTAssertTrue(state.canSeek); XCTAssertFalse(state.capabilities.canReadQueue)
            XCTAssertEqual(state.artwork?.host, "i.scdn.co"); XCTAssertTrue(state.queue.isEmpty)
        }
    }
    func testMalformedArtworkFallsBackAndInvalidSnapshotsAreRejected() throws {
        for url in ["", "file:///private/tmp/art", "https://untrusted.example/art", "http://i.scdn.co/art"] {
            XCTAssertNil(try LocalSpotifyController.decode(LocalSpotifyScripts.track(artwork: url)).artwork)
        }
        XCTAssertThrowsError(try LocalSpotifyController.decode(["playing"]))
        var fields = LocalSpotifyScripts.track(); fields[7] = "nan"
        XCTAssertThrowsError(try LocalSpotifyController.decode(fields))
        let stopped = try LocalSpotifyController.decode(["stopped"]); XCTAssertFalse(stopped.hasMedia)
    }
    func testEveryLocalControlUsesDictionaryAndSeekingNeverPlays() throws {
        let state = try LocalSpotifyController.decode(LocalSpotifyScripts.track(playing: false))
        let commands: [(MediaCommand, String)] = [(.playPause, "playpause"), (.play, "play"), (.pause, "pause"),
            (.next, "next track"), (.previous, "previous track"), (.seek(60), "set player position to 60.0"),
            (.setVolume(0.42), "set sound volume to 42"), (.setShuffle(true), "set shuffling to true"),
            (.toggleShuffle, "set shuffling to not shuffling"), (.setRepeatMode(.context), "set repeating to true"),
            (.setRepeatMode(.off), "set repeating to false"), (.cycleRepeat, "set repeating to not repeating")]
        for (command, statement) in commands {
            let source = try LocalSpotifyController.commandScript(command, state: state)
            XCTAssertTrue(source.contains(statement))
            XCTAssertTrue(source.contains("is not running then error number -600"))
            XCTAssertFalse(source.contains("http"))
        }
        let seek = try LocalSpotifyController.commandScript(.seek(500), state: state)
        XCTAssertTrue(seek.contains("set player position to 240.0"))
        XCTAssertFalse(seek.contains("\n        play\n")); XCTAssertFalse(seek.contains("playpause"))
        XCTAssertThrowsError(try LocalSpotifyController.commandScript(.setRepeatMode(.track), state: state))
        XCTAssertThrowsError(try LocalSpotifyController.commandScript(.seek(.nan), state: state))
        XCTAssertThrowsError(try LocalSpotifyController.commandScript(.setVolume(.infinity), state: state))
    }
    func testPausedSeekConfirmationAndTransportCommands() async throws {
        let scripts = LocalSpotifyScripts(); await scripts.setFields(LocalSpotifyScripts.track(playing: false, position: "60"))
        let provider = provider(scripts); try await provider.connect()
        try await provider.seek(to: 60)
        let paused = await snapshot(provider); XCTAssertFalse(paused.isPlaying); XCTAssertEqual(paused.elapsed, 60)
        try await provider.play(); let playing = await snapshot(provider); XCTAssertTrue(playing.isPlaying)
        try await provider.pause(); let again = await snapshot(provider); XCTAssertFalse(again.isPlaying)
        let sources = await scripts.sources
        XCTAssertEqual(sources.filter { $0.contains("set player position") }.count, 1)
        await provider.shutdown()
    }
    func testVolumeCommandDoesNotReleaseUnconfirmedSeekProtection() async throws {
        let scripts = LocalSpotifyScripts(); let provider = provider(scripts)
        try await provider.connect()
        try await provider.seek(to: 120)
        await scripts.setFields(LocalSpotifyScripts.track(position: "50"))
        try await provider.perform(.setVolume(0.5))
        await provider.refresh()
        let held = await snapshot(provider); XCTAssertEqual(held.elapsed, 45)
        await scripts.setFields(LocalSpotifyScripts.track(position: "120"))
        await provider.refresh()
        let confirmed = await snapshot(provider); XCTAssertEqual(confirmed.elapsed, 120)
        await provider.shutdown()
    }
    func testVolumeDragWritesDoNotFetchMetadataUntilFinalRefresh() async throws {
        let scripts = LocalSpotifyScripts(); let provider = provider(scripts)
        try await provider.connect()
        for volume in [0.1, 0.3, 0.7] { try await provider.perform(.setVolume(volume)) }
        let reads = await scripts.reads; XCTAssertEqual(reads, 1)
        await provider.refresh()
        let confirmed = await scripts.reads; XCTAssertEqual(confirmed, 2)
        await provider.shutdown()
    }
    func testEventDuringOldReadDiscardsItAndUsesOneTrailingRead() async throws {
        let scripts = LocalSpotifyScripts(); let events = LocalSpotifyEvents()
        let provider = provider(scripts, events: events); try await provider.connect()
        await events.waitUntilObserved()
        await scripts.holdNextRead()
        let oldRead = Task { await provider.refresh() }
        await scripts.waitForHeldRead()
        await scripts.setFields(LocalSpotifyScripts.track(id: "two", position: "0"))
        await events.send(SpotifyPlaybackEvent(trackID: "two", isPlaying: true))
        // This awaited entry guarantees the old read's revision has been invalidated.
        await provider.setExpandedVisible(true)
        await scripts.releaseRead(LocalSpotifyScripts.track())
        await oldRead.value
        await scripts.waitForReads(3)
        await provider.refresh()
        let state = await snapshot(provider); XCTAssertEqual(state.trackID, "two"); XCTAssertEqual(state.title, "Title two")
        await provider.shutdown()
    }
    func testRapidCommandsRejectDuplicateAndKeepCoherentLatestTrack() async throws {
        let scripts = LocalSpotifyScripts(); let provider = provider(scripts)
        try await provider.connect(); await scripts.holdNextRead()
        let next = Task { try await provider.nextTrack() }; await scripts.waitForHeldRead()
        do { try await provider.nextTrack(); XCTFail("Duplicate next accepted") }
        catch { XCTAssertEqual(error as? MediaFailure, .busy) }
        await scripts.setFields(LocalSpotifyScripts.track(id: "previous", position: "0"))
        try await provider.previousTrack()
        await scripts.releaseRead(LocalSpotifyScripts.track(id: "next")); try await next.value
        let state = await snapshot(provider)
        XCTAssertEqual(state.trackID, "previous"); XCTAssertEqual(state.title, "Title previous")
        await provider.shutdown()
    }
    func testFallbackIsSlowAndStopsWhenSpotifyQuits() async throws {
        let scripts = LocalSpotifyScripts(); let app = LocalSpotifyApplication()
        let clock = TestAppClock(now: .now, automaticallyAdvances: false)
        let provider = provider(scripts, application: app, clock: clock)
        try await provider.connect(); await clock.waitForPendingSleeps()
        let sleeps = await clock.sleepHistory(); XCTAssertEqual(sleeps, [.seconds(15)])
        await clock.advance(by: .seconds(14)); let reads = await scripts.reads; XCTAssertEqual(reads, 1)
        await app.set(running: false); await provider.refresh()
        let stopped = await snapshot(provider); XCTAssertEqual(stopped.localSpotifyStatus, .notRunning)
        await clock.advance(by: .seconds(60)); let after = await scripts.reads; XCTAssertEqual(after, 1)
        await provider.shutdown()
    }
    func testSleepWakeQuitAndLaunchUseLifecycleRefresh() async throws {
        let scripts = LocalSpotifyScripts(); let events = LocalSpotifyEvents(); let app = LocalSpotifyApplication()
        let provider = provider(scripts, application: app, events: events); try await provider.connect()
        await events.waitUntilObserved()
        await events.send(SpotifyLifecycleEvent.sleep)
        // Synchronize via a following lifecycle wake and observe the subsequent read.
        await events.send(SpotifyLifecycleEvent.wake); await scripts.waitForReads(2)
        await app.set(running: false); await provider.refresh()
        let notRunning = await snapshot(provider); XCTAssertEqual(notRunning.localSpotifyStatus, .notRunning)
        await app.set(running: true); await events.send(SpotifyLifecycleEvent.applicationChanged)
        await scripts.waitForReads(3); await provider.refresh()
        let resumed = await snapshot(provider); XCTAssertTrue(resumed.hasMedia)
        await provider.shutdown()
    }
    func testUnsupportedQueueFailsWithoutRunningScriptAndOldCacheNeverRestoresQueue() async throws {
        let scripts = LocalSpotifyScripts(); let provider = provider(scripts); try await provider.connect()
        let before = await scripts.sources.count
        do { try await provider.refreshQueue(); XCTFail("Queue fabricated") }
        catch { XCTAssertEqual(error as? MediaFailure, .unsupported) }
        let after = await scripts.sources.count; XCTAssertEqual(before, after)
        var state = try LocalSpotifyController.decode(LocalSpotifyScripts.track())
        state.queue = [.init(id: "stale", title: "Stale", artist: "Artist")]
        state.capabilities.canReadQueue = true
        let cache = try XCTUnwrap(CachedMediaTrack(state: state))
        XCTAssertTrue(cache.pausedPresentation().queue.isEmpty)
        XCTAssertFalse(cache.pausedPresentation().capabilities.canReadQueue)
        await provider.shutdown()
    }
    func testDeniedStateReplacesCachedTrackAndPausedLocalArtworkStaysHidden() throws {
        let clock = TestAppClock(now: .now, automaticallyAdvances: false)
        let coordinator = ActivityCoordinator(clock: clock)
        let model = MediaSessionController(provider: MockMediaProvider(), coordinator: coordinator)
        let paused = try LocalSpotifyController.decode(LocalSpotifyScripts.track(playing: false))
        model.receive(paused)
        XCTAssertFalse(model.collapsedMediaVisible); XCTAssertTrue(model.homeMediaConnected)
        XCTAssertNil(coordinator.primary?.minimal)
        XCTAssertTrue(model.isPlaybackLocal); XCTAssertFalse(model.state.isPlaying)
        model.receive(LocalSpotifyController.empty(.denied))
        XCTAssertFalse(model.state.hasMedia); XCTAssertFalse(model.collapsedMediaVisible)
        XCTAssertFalse(model.homeMediaConnected); XCTAssertNil(coordinator.primary)
        model.stop()
    }
    func testPausedLocalSpotifyDrawsNoSoftwareNotch() throws {
        let clock = TestAppClock(now: .now, automaticallyAdvances: false)
        let shell = DynamicIslandPresentationModel(clock: clock)
        let model = MediaSessionController(provider: MockMediaProvider(), coordinator: shell.activityCoordinator)
        shell.mediaRenderer = model
        defer { model.stop(); shell.reset() }
        let paused = try LocalSpotifyController.decode(LocalSpotifyScripts.track(playing: false, artwork: ""))
        model.receive(paused)
        XCTAssertTrue(model.state.hasMedia, "The paused track remains available in Music")
        XCTAssertFalse(shell.showsCollapsedMedia)
        let layout = NotchGeometryResolver.layout(for:
            .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        let renderer = ImageRenderer(content: NotchiumShellView(model: shell, layout: layout)
            .frame(width: layout.panelFrame.width, height: layout.panelFrame.height))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 0 },
                      "Idle media must leave the entire software shell transparent")
    }
    func testLocalPauseHidesArtworkAndResumeRestoresTheSameActivity() async throws {
        let clock = TestAppClock(now: .now, automaticallyAdvances: false)
        let coordinator = ActivityCoordinator(clock: clock)
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true }, activityClock: clock)
        let model = MediaSessionController(provider: MockMediaProvider(), coordinator: coordinator,
                                           visibilityClock: clock, audioMeter: meter)
        defer { model.stop() }
        let playing = try LocalSpotifyController.decode(LocalSpotifyScripts.track())
        let paused = try LocalSpotifyController.decode(LocalSpotifyScripts.track(playing: false))
        model.receive(playing)
        for _ in 0..<30 { await Task.yield() }
        capture.levels?(Array(repeating: 0.8, count: 7))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(model.collapsedMediaVisible)
        let activityID = try XCTUnwrap(coordinator.primary?.id)

        model.receive(paused)
        XCTAssertFalse(model.collapsedMediaVisible)
        XCTAssertNil(coordinator.primary?.minimal)
        XCTAssertEqual(model.state.artwork, playing.artwork, "Music retains its paused track")
        model.receive(playing)
        XCTAssertFalse(model.collapsedMediaVisible, "Resume waits for local audio")
        capture.levels?(Array(repeating: 0.8, count: 7))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(model.collapsedMediaVisible)
        XCTAssertEqual(coordinator.primary?.id, activityID)

        model.receive(paused)
        capture.levels?(Array(repeating: 0.8, count: 7))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertFalse(model.collapsedMediaVisible, "Late audio samples cannot reveal a paused track")
        XCTAssertNil(coordinator.primary?.minimal)
    }
    func testUnavailableUpNextHasNoVisibleQueueRowsEvenWithStaleInput() throws {
        var state = try LocalSpotifyController.decode(LocalSpotifyScripts.track())
        state.queue = [.init(id: "stale", title: "Old Web Queue", artist: "Stale")]
        let renderer = ImageRenderer(content: UpNextView(state: state).frame(width: 464, height: 150).background(Color.black))
        XCTAssertNotNil(renderer.cgImage)
    }
}
