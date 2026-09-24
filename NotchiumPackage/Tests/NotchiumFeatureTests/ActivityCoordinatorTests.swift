import Combine
import Foundation
import NotchiumCore
@testable import NotchiumDynamicIsland
@testable import NotchiumFeature
import XCTest

@MainActor
final class ActivityCoordinatorTests: XCTestCase {
    private func activity(
        _ kind: NotchActivityKind,
        priority: NotchActivityPriority? = nil,
        duration: Duration? = nil,
        timestamp: Date = .now
    ) -> NotchActivity {
        NotchActivity(
            id: UUID(),
            kind: kind,
            title: kind.rawValue,
            subtitle: nil,
            priority: priority,
            timestamp: timestamp,
            duration: duration
        )
    }

    private func clock() -> TestAppClock {
        TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
    }

    func testMusicIsPersistentAndDoesNotOccupyTransientSlot() {
        let coordinator = ActivityCoordinator(clock: clock())
        let music = activity(.media)
        let calendar = activity(.calendar, duration: .seconds(10))

        coordinator.present(music)
        coordinator.present(calendar)

        XCTAssertEqual(coordinator.persistentActivity, music)
        XCTAssertEqual(coordinator.activeTransient, calendar)
        XCTAssertEqual(coordinator.activeActivity, calendar)
        XCTAssertEqual(coordinator.presentationMode, .combined)
        XCTAssertEqual(coordinator.queueCount, 0)
    }

    func testAudioVisuallySupersedesMusicWithoutDiscardingIt() {
        let coordinator = ActivityCoordinator(clock: clock())
        let music = activity(.media)
        let audio = activity(.systemHUD, duration: .milliseconds(1250))

        coordinator.present(music)
        coordinator.present(audio)

        XCTAssertEqual(coordinator.presentationMode, .compactHUD)
        XCTAssertEqual(coordinator.persistentActivity, music)
        coordinator.dismissActive()
        XCTAssertEqual(coordinator.activeActivity, music)
        XCTAssertEqual(coordinator.presentationMode, .mediaSides)
    }

    func testHigherPriorityPreemptsAndUnexpiredActivityCanResume() {
        let coordinator = ActivityCoordinator(clock: clock())
        let audio = activity(.systemHUD, priority: .low, duration: .seconds(5))
        let calendar = activity(.calendar, priority: .high, duration: .seconds(10))

        coordinator.present(audio)
        coordinator.present(calendar)

        XCTAssertEqual(coordinator.activeTransient, calendar)
        XCTAssertEqual(coordinator.queueCount, 1)
        coordinator.dismissActive()
        XCTAssertEqual(coordinator.activeTransient, audio)
    }

    func testEqualPriorityKeepsActiveAndBuffersOnePerFamily() {
        let coordinator = ActivityCoordinator(clock: clock())
        let calendar = activity(.calendar, priority: .medium, duration: .seconds(10))
        let firstAudio = activity(.audioDevice, priority: .medium, duration: .seconds(2))
        let updatedAudio = activity(.systemHUD, priority: .low, duration: .seconds(2))

        coordinator.present(calendar)
        coordinator.present(firstAudio)
        coordinator.present(updatedAudio)

        XCTAssertEqual(coordinator.activeTransient, calendar)
        XCTAssertEqual(coordinator.queueCount, 1)
        coordinator.dismissActive()
        XCTAssertEqual(coordinator.activeTransient?.id, updatedAudio.id)
        XCTAssertEqual(coordinator.activeTransient?.kind, .systemHUD)
        XCTAssertEqual(coordinator.activeTransient?.priority, .medium)
    }

    func testPendingAudioExpiresAgainstItsOriginalDeadline() async {
        let clock = clock()
        let coordinator = ActivityCoordinator(clock: clock)
        let audio = activity(.systemHUD, priority: .low, duration: .milliseconds(1250))
        let calendar = activity(.calendar, priority: .high, duration: .seconds(10))

        coordinator.present(audio)
        await clock.waitForPendingSleeps()
        coordinator.present(calendar)
        await drainMainActorTasks()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(2))
        await drainMainActorTasks()

        XCTAssertEqual(coordinator.activeTransient, calendar)
        XCTAssertEqual(coordinator.queueCount, 0)
        coordinator.dismissActive()
        XCTAssertNil(coordinator.activeTransient)
    }

    func testTimedActivityExpiresAtCoordinatorDeadline() async {
        let clock = clock()
        let coordinator = ActivityCoordinator(clock: clock)
        let timed = activity(.calendar, duration: .seconds(3))

        coordinator.present(timed)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(2))
        await drainMainActorTasks()
        XCTAssertEqual(coordinator.activeTransient, timed)

        await expectTransient(nil, on: coordinator) {
            await clock.advance(by: .seconds(1))
        }
    }

    func testHoverPausesAndResumesTransientDeadline() async {
        let clock = clock()
        let coordinator = ActivityCoordinator(clock: clock)
        let audio = activity(.systemHUD, duration: .seconds(2))

        coordinator.present(audio)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(500))
        coordinator.setHovered(true)
        await drainMainActorTasks()
        await clock.advance(by: .seconds(10))
        await drainMainActorTasks()
        XCTAssertEqual(coordinator.activeTransient, audio)

        coordinator.setHovered(false)
        await drainMainActorTasks()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(1))
        await drainMainActorTasks()
        XCTAssertEqual(coordinator.activeTransient, audio)
        await expectTransient(nil, on: coordinator) {
            await clock.advance(by: .milliseconds(500))
        }
    }

    func testExpandedSurfaceIsNeverTakenOverByActivity() {
        let model = DynamicIslandPresentationModel(clock: clock())
        model.present(.expanded, animated: false)
        model.pageModel.selectedPage = .calendar

        model.activityCoordinator.present(activity(.notification, duration: .seconds(3)))

        XCTAssertEqual(model.presentationState, .expanded)
        XCTAssertEqual(model.visualState, .expanded)
        XCTAssertEqual(model.pageModel.selectedPage, .calendar)
    }

    func testActivatingTransientDismissesItAndOpensDeclaredDestination() {
        let model = DynamicIslandPresentationModel(clock: clock())
        model.pageModel.selectedPage = .music
        model.activityCoordinator.present(activity(.calendar, duration: .seconds(10)))

        model.activateCurrentActivity()

        XCTAssertNil(model.activityCoordinator.activeTransient)
        XCTAssertEqual(model.pageModel.selectedPage, .calendar)
        XCTAssertEqual(model.visualState, .expanded)
    }

    func testDismissAndClearOperationsPreserveTheirScope() {
        let coordinator = ActivityCoordinator(clock: clock())
        let music = activity(.media)
        let calendar = activity(.calendar, priority: .high, duration: .seconds(10))
        let audio = activity(.systemHUD, priority: .low, duration: .seconds(2))
        coordinator.present(music)
        coordinator.present(calendar)
        coordinator.present(audio)

        coordinator.clearQueue()
        XCTAssertEqual(coordinator.queueCount, 0)
        XCTAssertEqual(coordinator.activeTransient, calendar)
        XCTAssertEqual(coordinator.persistentActivity, music)

        coordinator.dismiss(kind: .calendar)
        XCTAssertNil(coordinator.activeTransient)
        XCTAssertEqual(coordinator.persistentActivity, music)
        coordinator.clearAll()
        XCTAssertNil(coordinator.activeActivity)
    }

    func testMockCatalogUsesTypedKindPriorities() {
        XCTAssertEqual(Set(MockNotchActivity.allCases.map(\.kind)), Set(NotchActivityKind.allCases))
        for event in MockNotchActivity.allCases {
            let mock = event.activity(id: UUID())
            XCTAssertEqual(mock.priority, mock.kind.priority)
        }
    }

    private func expectTransient(
        _ expected: NotchActivity?,
        on coordinator: ActivityCoordinator,
        action: () async -> Void
    ) async {
        let (stream, continuation) = AsyncStream<NotchActivity?>.makeStream()
        let subscription = coordinator.$activeTransient.sink { continuation.yield($0) }
        defer {
            subscription.cancel()
            continuation.finish()
        }
        await action()
        for await value in stream where value == expected { break }
        XCTAssertEqual(coordinator.activeTransient, expected)
    }
}
