import NotchiumCore
import NotchiumDynamicIsland
@testable import NotchiumMediaFeature
import NotchiumServices
import XCTest

private actor DisplayVisibilityMediaProvider: MediaProviding {
    var expanded = false
    var queueRefreshes = 0
    func availability() -> FeatureAvailability { .available }
    func updates() -> AsyncStream<MediaState> { AsyncStream { $0.finish() } }
    func perform(_ command: MediaCommand) {}
    func setExpandedVisible(_ visible: Bool) { expanded = visible }
    func refreshQueue() { queueRefreshes += 1 }
}

@MainActor
final class MediaDisplayVisibilityTests: XCTestCase {
    func testClosingOneMusicPageKeepsAnotherDisplaysProviderVisible() async {
        let provider = DisplayVisibilityMediaProvider()
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(clock: clock), visibilityClock: clock)
        defer { model.stop() }
        await model.setExpandedVisible(true, source: "builtIn")
        await model.setExpandedVisible(false, source: "external")
        var expanded = await provider.expanded
        XCTAssertTrue(expanded)
        await model.setExpandedVisible(true, source: "external")
        await model.removePresentation(source: "builtIn")
        expanded = await provider.expanded
        XCTAssertTrue(expanded)
        await model.removePresentation(source: "external")
        expanded = await provider.expanded
        XCTAssertFalse(expanded)
    }

    func testRemovingOneDisplayDoesNotCancelAnotherDisplaysUpNextRefresh() async {
        let provider = DisplayVisibilityMediaProvider()
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let model = MediaFeatureModel(provider: provider, coordinator: ActivityCoordinator(clock: clock), visibilityClock: clock)
        model.receive(.init(playbackState: .paused, title: "Fixture", source: .spotify,
                            capabilities: .init(canReadQueue: true)))
        defer { model.stop() }
        model.setUpNextVisible(true, source: "builtIn")
        model.setUpNextVisible(true, source: "external")
        await clock.waitForPendingSleeps()
        await model.removePresentation(source: "builtIn")
        var pending = await clock.pendingSleepCount()
        XCTAssertEqual(pending, 1, "A second visible Up Next must retain the shared refresh task")
        await model.removePresentation(source: "external")
        for _ in 0..<1000 {
            if await clock.pendingSleepCount() == 0 { break }
            await Task.yield()
        }
        pending = await clock.pendingSleepCount()
        XCTAssertEqual(pending, 0)
    }
}
