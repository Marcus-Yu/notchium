import Combine
import Foundation
import NotchiumCore
@testable import NotchiumDynamicIsland
@testable import NotchiumFeature
import XCTest

@MainActor
final class ActivityCoordinatorTests: XCTestCase {
    private func activity(_ kind: NotchActivityKind = .media,
                          duration: Duration? = nil) -> NotchActivity {
        NotchActivity(id: UUID(), kind: kind, title: kind.rawValue,
                      subtitle: nil, priority: kind.priority, duration: duration)
    }

    private func clock() -> TestAppClock {
        TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
    }

    func testIdleShowsActivityAndRepeatedIdentityIsIgnored() {
        let coordinator = ActivityCoordinator(clock: clock())
        let media = activity()
        coordinator.present(media)
        coordinator.present(media)
        XCTAssertEqual(coordinator.activeActivity, media)
        XCTAssertEqual(coordinator.queueCount, 0)
    }

    func testHigherPriorityInterruptsAndDismissalRestoresQueue() {
        let coordinator = ActivityCoordinator(clock: clock())
        let media = activity()
        let meeting = activity(.meeting)
        coordinator.present(media)
        coordinator.present(meeting)
        XCTAssertEqual(coordinator.activeActivity, meeting)
        XCTAssertEqual(coordinator.queueCount, 1)
        coordinator.dismissActive()
        XCTAssertEqual(coordinator.activeActivity, media)
        XCTAssertEqual(coordinator.queueCount, 0)
    }

    func testLowerPriorityQueuesAndHighestQueuedWins() {
        let coordinator = ActivityCoordinator(clock: clock())
        let notification = activity(.notification)
        let media = activity()
        let battery = activity(.battery)
        coordinator.present(notification)
        coordinator.present(media)
        coordinator.present(battery)
        XCTAssertEqual(coordinator.activeActivity, notification)
        XCTAssertEqual(coordinator.queueCount, 2)
        coordinator.dismissActive()
        XCTAssertEqual(coordinator.activeActivity, battery)
        coordinator.dismissActive()
        XCTAssertEqual(coordinator.activeActivity, media)
    }

    func testEqualPriorityPreservesQueueFIFOIncludingInterruptedActivity() {
        let coordinator = ActivityCoordinator(clock: clock())
        let first = activity(.meeting)
        let second = activity(.clipboard)
        let third = activity(.meeting)
        coordinator.present(first)
        coordinator.present(second)
        coordinator.present(third)
        coordinator.present(activity(.notification))
        // The interrupted activity joins the tail of the queue at interruption.
        for expected in [second, third, first] {
            coordinator.dismissActive()
            XCTAssertEqual(coordinator.activeActivity, expected)
        }
    }

    func testTimedActivityExpiresOnlyAfterFakeDeadline() async {
        let clock = clock()
        let coordinator = ActivityCoordinator(clock: clock)
        let timed = activity(duration: .seconds(3))
        coordinator.present(timed)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(2))
        XCTAssertEqual(coordinator.activeActivity, timed)
        await expectActivity(nil, on: coordinator) { await clock.advance(by: .seconds(1)) }
    }

    func testNilDurationRemainsAndSchedulesNoTimeout() async {
        let clock = clock()
        let coordinator = ActivityCoordinator(clock: clock)
        let media = activity()
        coordinator.present(media)
        await clock.advance(by: .seconds(86_400))
        XCTAssertEqual(coordinator.activeActivity, media)
        let history = await clock.sleepHistory()
        XCTAssertTrue(history.isEmpty)
    }

    func testCancelledTimeoutCannotDismissReplacement() async {
        let clock = clock()
        let coordinator = ActivityCoordinator(clock: clock)
        let media = activity(duration: .seconds(3))
        let notification = activity(.notification)
        coordinator.present(media)
        await clock.waitForPendingSleeps()
        coordinator.present(notification)
        await clock.advance(by: .seconds(10))
        await drainMainActorTasks()
        XCTAssertEqual(coordinator.activeActivity, notification)
        coordinator.dismissActive()
        await clock.waitForPendingSleeps()
        await expectActivity(nil, on: coordinator) { await clock.advance(by: .seconds(3)) }
    }

    func testClearQueueAndDismissByIdentity() {
        let coordinator = ActivityCoordinator(clock: clock())
        let notification = activity(.notification)
        let media = activity()
        coordinator.present(notification)
        coordinator.present(media)
        coordinator.dismiss(id: media.id)
        XCTAssertEqual(coordinator.queueCount, 0)
        XCTAssertEqual(coordinator.activeActivity, notification)
        coordinator.present(activity(.battery))
        coordinator.clearQueue()
        XCTAssertEqual(coordinator.queueCount, 0)
        XCTAssertEqual(coordinator.activeActivity, notification)
        coordinator.dismiss(id: notification.id)
        XCTAssertNil(coordinator.activeActivity)
    }

    func testManualExpansionAndPageSurviveCriticalInterruption() {
        let model = DynamicIslandPresentationModel(clock: clock())
        model.present(.expanded, animated: false)
        model.pageModel.selectedPage = .calendar
        model.activityCoordinator.present(activity(.battery))
        XCTAssertEqual(model.presentationState, .expanded)
        model.activityCoordinator.present(activity(.notification))
        XCTAssertEqual(model.presentationState, .activity)
        XCTAssertEqual(model.visualState, .expanded)
        model.activityCoordinator.dismissActive()
        XCTAssertEqual(model.presentationState, .expanded)
        XCTAssertEqual(model.visualState, .expanded)
        XCTAssertEqual(model.pageModel.selectedPage, .calendar)
    }

    func testExpandedPageSelectionSurvivesMediaActivityChanges() {
        let model = DynamicIslandPresentationModel(clock: clock())
        model.present(.expanded, animated: false)
        model.pageModel.selectedPage = .calendar
        let media = activity(.media)
        model.activityCoordinator.present(media)
        XCTAssertEqual(model.pageModel.selectedPage, .calendar)
        model.activityCoordinator.dismiss(id: media.id)
        XCTAssertEqual(model.pageModel.selectedPage, .calendar)
    }

    func testOpeningCollapsedCalendarActivitySelectsCalendar() {
        let model = DynamicIslandPresentationModel(clock: clock())
        model.activityCoordinator.present(activity(.calendar))
        XCTAssertEqual(model.pageModel.selectedPage, .calendar)

        model.pageModel.selectedPage = .music
        model.setExpanded(true)
        XCTAssertEqual(model.pageModel.selectedPage, .calendar)
    }

    func testHoverOverridesNonCriticalActivityAndDismissalRestoresPassive() async {
        let clock = clock()
        let model = DynamicIslandPresentationModel(clock: clock)
        model.activityCoordinator.present(activity())
        XCTAssertEqual(model.presentationState, .activity)
        model.setHovered(true)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(120))
        await drainMainActorTasks()
        XCTAssertEqual(model.presentationState, .expanded)
        XCTAssertEqual(model.visualState, .hovered)
        model.collapse()
        XCTAssertEqual(model.presentationState, .activity)
        model.activityCoordinator.dismissActive()
        XCTAssertEqual(model.presentationState, .passive)
        model.reset()
    }

    func testMockCatalogUsesExactPrioritiesAndAllKinds() {
        let expected: [NotchActivityKind: Int] = [
            .systemHUD: 10, .media: 20, .charging: 30, .audioDevice: 30,
            .download: 40, .screenshot: 40, .calendar: 15, .focus: 60,
            .battery: 70, .meeting: 80, .clipboard: 80, .notification: 100
        ]
        let coordinator = ActivityCoordinator(clock: clock())
        XCTAssertEqual(Set(MockNotchActivity.allCases.map(\.kind)), Set(NotchActivityKind.allCases))
        for event in MockNotchActivity.allCases {
            let mock = event.activity(id: UUID())
            XCTAssertEqual(mock.priority, expected[mock.kind])
            coordinator.present(mock)
            XCTAssertEqual(coordinator.activeActivity, mock)
            coordinator.clearAll()
        }
        coordinator.present(activity())
        coordinator.present(activity(.notification))
        coordinator.dismiss(kind: .media)
        XCTAssertEqual(coordinator.queueCount, 0)
        XCTAssertEqual(coordinator.activeActivity?.kind, .notification)
    }

    private func expectActivity(_ expected: NotchActivity?, on coordinator: ActivityCoordinator,
                                action: () async -> Void) async {
        // Publisher synchronization, not a wall-clock timeout or real sleep.
        let (stream, continuation) = AsyncStream<NotchActivity?>.makeStream()
        let subscription = coordinator.$activeActivity.sink { continuation.yield($0) }
        defer {
            subscription.cancel()
            continuation.finish()
        }
        await action()
        for await value in stream where value == expected { break }
        XCTAssertEqual(coordinator.activeActivity, expected)
    }
}
