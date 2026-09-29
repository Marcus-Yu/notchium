import Foundation
import XCTest
import NotchiumCore
@testable import NotchiumDynamicIsland

@MainActor
final class NavigationOwnershipTests: XCTestCase {
    func testCollapseReversalRetainsManualPageUntilCollapseCompletes() async {
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(clock: clock)
        defer { model.reset() }
        model.activityCoordinator.present(.init(id: UUID(), kind: .media, title: "Track", subtitle: nil,
            lifetime: .persistent, duration: nil, payload: .mediaPlayback(isPlaying: true)))
        model.setExpanded(true)
        XCTAssertEqual(model.pageModel.selectedPage, .music)
        model.pageModel.selectedPage = .home
        XCTAssertTrue(model.pageModel.manualSelectionDuringExpansion)
        model.collapse()
        model.setExpanded(true)
        XCTAssertEqual(model.pageModel.selectedPage, .home)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(1))
        await drainMainActorTasks()
        XCTAssertEqual(model.pageModel.selectedPage, .home)
        model.collapse()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(1))
        await drainMainActorTasks()
        XCTAssertEqual(model.phase, .collapsed)
        XCTAssertFalse(model.pageModel.manualSelectionDuringExpansion)
        model.setExpanded(true)
        XCTAssertEqual(model.pageModel.selectedPage, .music)
    }

    func testLatestClickWinsAcrossActivityUpdatesAndDefaultReconciliation() {
        let model = DynamicIslandPresentationModel()
        defer { model.reset() }
        model.setExpanded(true)
        for page in [NotchPage.home, .music, .calendar, .audio, .home] {
            model.pageModel.selectedPage = page
            model.activityCoordinator.present(.init(id: UUID(), kind: .media, title: "Changed track", subtitle: nil,
                lifetime: .persistent, duration: nil, payload: .mediaPlayback(isPlaying: true)))
            model.pageModel.selectDefaultPage()
            model.setExpanded(true)
            XCTAssertEqual(model.pageModel.selectedPage, page)
        }
    }
}
