import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
final class Stage21ActivityPolicyTests: XCTestCase {
    func testImportantEventsSurfaceAcrossImmersiveAndPresentationContexts() {
        for context in [NotchPresentationContext.fullscreenApp, .immersiveMedia, .presentationLike] {
            for kind in [NotchNotification.Kind.volume, .mute, .criticalBattery, .focusTimerComplete,
                         .reminder5, .transferFinished, .transferFailed, .actionSucceeded, .reminderAdded] {
                let notice = NotchNotification.feedback("Fixture", kind: kind, key: "fixture")
                XCTAssertTrue(ActivitySurfacingPolicy.shouldSurface(notice.activity, notificationKind: kind, in: context))
            }
            let brightness = NotchActivity(id: UUID(), kind: .systemHUD, title: "Brightness", subtitle: nil, duration: .seconds(1))
            XCTAssertTrue(ActivitySurfacingPolicy.shouldSurface(brightness, in: context))
        }
    }

    func testQuietingKeepsIdentityAndDeadlineWithoutChangingRanking() async {
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let coordinator = ActivityCoordinator(clock: clock)
        let minor = NotchNotification.charging(level: 0.5)
        coordinator.notifications.present(minor)
        await drainMainActorTasks()
        let deadline = coordinator.notifications.expiresAt
        coordinator.setPresentationContext(.immersiveMedia)
        XCTAssertNil(coordinator.primary)
        XCTAssertTrue(coordinator.contains(id: minor.id))
        XCTAssertEqual(coordinator.liveActivities.map(\.id), [minor.id])
        coordinator.setPresentationContext(.normal)
        XCTAssertEqual(coordinator.primary?.id, minor.id)
        XCTAssertEqual(coordinator.notifications.expiresAt, deadline)
        coordinator.setPresentationContext(.presentationLike)
        await clock.advance(by: .seconds(3))
        await waitUntil { !coordinator.contains(id: minor.id) }
        coordinator.setPresentationContext(.normal)
        XCTAssertNil(coordinator.primary, "Quiet notices still expire; returning to Desktop cannot replay them")
        coordinator.clearAll()
    }

    func testCalendarAndDownloadRestoreAfterVolumeAndSleepPreservesData() {
        let coordinator = ActivityCoordinator(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
        defer { coordinator.clearAll() }
        let download = NotchActivity(id: UUID(), kind: .download, title: "Transfer", subtitle: nil,
                                     lifetime: .persistent, duration: nil, minimal: .progress(0.5))
        coordinator.present(download)
        coordinator.setPresentationContext(.fullscreenApp)
        let calendar = NotchNotification.feedback("Calendar", kind: .reminder5, key: "calendar.fixture")
        coordinator.notifications.present(calendar)
        XCTAssertEqual(coordinator.primary?.id, calendar.id)
        let volume = NotchNotification.feedback("Volume", kind: .volume, key: "audio.level")
        coordinator.notifications.present(volume)
        XCTAssertEqual(coordinator.primary?.id, calendar.id, "Environmental policy never raises volume priority")
        coordinator.setPresentationContext(.sleeping)
        XCTAssertNil(coordinator.primary)
        XCTAssertTrue(coordinator.contains(id: download.id))
        XCTAssertTrue(coordinator.contains(id: calendar.id))
        coordinator.setPresentationContext(.normal)
        XCTAssertEqual(coordinator.primary?.id, calendar.id)
        coordinator.dismissActive()
        XCTAssertEqual(coordinator.primary?.id, download.id)
    }
}
