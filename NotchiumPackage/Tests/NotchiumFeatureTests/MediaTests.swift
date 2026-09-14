import AppKit
import SwiftUI
import XCTest
import NotchiumCore
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature
@testable import NotchiumServices

@MainActor final class MediaTests: XCTestCase {
    private func presentation() -> DynamicIslandPresentationModel {
        .init(clock: TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false))
    }
    func testPassivePlayingPausedStoppedAndFrozenDimensions() async throws {
        let presentation = presentation()
        let provider = MockMediaProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: presentation.activityCoordinator)
        presentation.mediaRenderer = model
        model.receive(await provider.snapshot)
        XCTAssertEqual(presentation.presentationState, .passive)
        try await provider.apply(.play)
        model.receive(await provider.snapshot)
        XCTAssertEqual(presentation.activityCoordinator.activeActivity?.priority, 20)
        XCTAssertTrue(presentation.showsCollapsedMedia)
        XCTAssertEqual(presentation.surfaceState, .collapsed)
        XCTAssertEqual(presentation.pageModel.selectedPage, .media)
        try await provider.apply(.pause)
        model.receive(await provider.snapshot)
        XCTAssertFalse(model.state.isPlaying)
        XCTAssertTrue(presentation.showsCollapsedMedia)
        presentation.present(.hovered, animated: false)
        XCTAssertEqual(presentation.surfaceState, .hovered)
        XCTAssertFalse(presentation.showsCollapsedMedia)
        XCTAssertEqual(NotchGeometryResolver.expandedNotchSize, CGSize(width: 450, height: 190))
        presentation.present(.collapsed, animated: false)
        try await provider.apply(.stop)
        model.receive(await provider.snapshot)
        XCTAssertEqual(presentation.presentationState, .passive)
        XCTAssertNil(presentation.activityCoordinator.activeActivity)
    }
    func testMediaInterruptsRestoresWithoutDuplicatesAndStopRemovesQueuedMedia() async throws {
        let presentation = presentation()
        let provider = MockMediaProvider()
        let model = MediaFeatureModel(provider: provider, coordinator: presentation.activityCoordinator)
        presentation.mediaRenderer = model
        try await provider.apply(.play)
        let playing = await provider.snapshot
        model.receive(playing)
        let id = presentation.activityCoordinator.activeActivity?.id
        let alert = NotchActivity(id: UUID(), kind: .notification, title: "Test alert", subtitle: nil, priority: 100, duration: nil)
        presentation.activityCoordinator.present(alert)
        for _ in 0..<100 { model.receive(playing) }
        XCTAssertEqual(presentation.activityCoordinator.queueCount, 1)
        XCTAssertFalse(presentation.showsCollapsedMedia)
        presentation.activityCoordinator.dismissActive()
        XCTAssertEqual(presentation.activityCoordinator.activeActivity?.id, id)
        XCTAssertTrue(presentation.showsCollapsedMedia)
        presentation.activityCoordinator.present(alert)
        model.receive(.init())
        presentation.activityCoordinator.dismissActive()
        XCTAssertNil(presentation.activityCoordinator.activeActivity)
    }
    func testMockCommandsAndSeekClamp() async throws {
        let provider = MockMediaProvider()
        try await provider.apply(.play)
        let initial = await provider.snapshot
        try await provider.perform(.playPause)
        var state = await provider.snapshot
        XCTAssertEqual(state.playbackState, .paused)
        try await provider.perform(.playPause)
        try await provider.perform(.next)
        state = await provider.snapshot
        XCTAssertTrue(state.isPlaying); XCTAssertNotEqual(state.trackID, initial.trackID)
        try await provider.perform(.previous)
        state = await provider.snapshot
        XCTAssertEqual(state.trackID, initial.trackID)
        try await provider.perform(.seek(122))
        state = await provider.snapshot
        XCTAssertEqual(state.progress, 0.5)
        try await provider.perform(.seek(-50))
        state = await provider.snapshot; XCTAssertEqual(state.elapsedTime, 0)
        try await provider.perform(.seek(9999))
        state = await provider.snapshot; XCTAssertEqual(state.progress, 1)
        try await provider.perform(.toggleShuffle)
        try await provider.perform(.cycleRepeat)
        state = await provider.snapshot
        XCTAssertEqual(state.shuffle, true); XCTAssertEqual(state.repeatMode, .context)
    }
    func testFixturesMissingArtworkLongTitleSourcesAndQueue() async throws {
        let provider = MockMediaProvider()
        for fixture in MediaFixture.allCases {
            try await provider.apply(.play)
            try await provider.apply(fixture)
        }
        try await provider.apply(.noArtwork)
        var state = await provider.snapshot; XCTAssertNil(state.artwork); XCTAssertTrue(state.hasMedia)
        try await provider.apply(.longTitle)
        state = await provider.snapshot
        XCTAssertEqual(state.collapsedTitle.count, 120); XCTAssertTrue(state.collapsedTitle.hasSuffix("…"))
        XCTAssertGreaterThan(state.title!.count, state.collapsedTitle.count)
        try await provider.apply(.spotify)
        state = await provider.snapshot; XCTAssertEqual(state.source, .spotify)
        try await provider.apply(.appleMusic)
        state = await provider.snapshot; XCTAssertEqual(state.source, .appleMusic)
        try await provider.apply(.queue)
        state = await provider.snapshot; XCTAssertEqual(state.queue?.count, 2)
        XCTAssertEqual(Set(state.queue!.map(\.id)).count, 2)
    }
    func testInvalidProgressAndUnsupportedCommands() async throws {
        for duration in [0.0, -1, .infinity, .nan] {
            let state = MediaState(playbackState: .playing, title: "Test", elapsed: .nan, duration: duration)
            XCTAssertEqual(state.progress, 0); XCTAssertFalse(state.canSeek)
        }
        let provider = MockMediaProvider(snapshot: .init(playbackState: .playing, title: "Read only"))
        do { try await provider.perform(.playPause); XCTFail("Unsupported command accepted") }
        catch { XCTAssertEqual(error as? MediaFailure, .unsupported) }
        let commands = await provider.commands
        XCTAssertTrue(commands.isEmpty)
    }
    func testProviderStreamPublishesCommandsAndStopsWithoutSleeps() async throws {
        let provider = MockMediaProvider()
        var iterator = await provider.updates().makeAsyncIterator()
        let empty = await iterator.next(); XCTAssertFalse(empty!.hasMedia)
        try await provider.apply(.play)
        let playing = await iterator.next(); XCTAssertTrue(playing!.isPlaying)
        try await provider.perform(.playPause)
        let paused = await iterator.next(); XCTAssertEqual(paused!.playbackState, .paused)
        try await provider.apply(.stop)
        let stopped = await iterator.next(); XCTAssertFalse(stopped!.hasMedia)
    }
    func testFeatureCommandsRouteThroughProvider() async throws {
        let provider = MockMediaProvider()
        try await provider.apply(.play)
        let model = MediaFeatureModel(provider: provider, coordinator: presentation().activityCoordinator)
        var iterator = await provider.updates().makeAsyncIterator()
        let initial = await iterator.next()
        model.receive(initial!)
        model.send(.playPause)
        let paused = await iterator.next()
        XCTAssertEqual(paused?.playbackState, .paused)
        let commands = await provider.commands
        XCTAssertEqual(commands, [.playPause])
        model.stop()
    }
    func testStageFourEnablesOnlyMediaAndShell() {
        for flag in FeatureFlag.allCases {
            XCTAssertEqual(FeatureFlags.stageFourMedia[flag], flag == .media || flag == .notchShell)
        }
    }
    func testArtworkAndExpandedContentRender() async throws {
        let provider = MockMediaProvider()
        try await provider.apply(.play)
        let model = MediaFeatureModel(provider: provider, coordinator: presentation().activityCoordinator)
        model.receive(await provider.snapshot)
        let expanded = ImageRenderer(content: MediaPageView(model: model).frame(width: 450, height: 140).background(.black))
        let collapsed = ImageRenderer(content: CollapsedMediaView(model: model, hardwareWidth: 180)
            .frame(width: 380, height: 32).background(.black))
        for (name, renderer) in [("expanded", expanded.nsImage), ("collapsed", collapsed.nsImage)] {
            let image = try XCTUnwrap(renderer)
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-media-\(name).png"))
        }
    }
}
