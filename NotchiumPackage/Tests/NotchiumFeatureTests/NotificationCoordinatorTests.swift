import Foundation
import NotchiumCore
import NotchiumServices
@testable import NotchiumCalendarFeature
@testable import NotchiumDynamicIsland
import SwiftUI
import XCTest

@MainActor
final class NotificationCoordinatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func calendar(priority: NotchActivityPriority = .high, key: String = "meeting") -> NotchNotification {
        .init(kind: priority == .high ? .reminder5 : .reminder30,
              duration: .seconds(10), coalescingKey: key, action: .calendar,
              presentationStyle: .calendar, content: .calendar(title: "Planning", status: "5 min"))
    }
    private func audio(_ level: Double = 0.5, muted: Bool = false, output: Bool = false) -> NotchNotification {
        .audio(.init(kind: output ? .outputChanged : .volume, deviceName: "AirPods Pro", volume: level, isMuted: muted))
    }
    private func drain() async { for _ in 0..<100 { await Task.yield() } }

    func testCalendarPriorityDropsVolumeWithoutQueueOrTimeoutReset() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let notifications = activities.notifications
        let reminder = calendar()
        XCTAssertTrue(notifications.present(reminder))
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(6))
        for level in [0.5, 0.54, 0.58, 0.62] { XCTAssertFalse(notifications.present(audio(level))) }
        XCTAssertFalse(notifications.present(audio(output: true)))
        XCTAssertEqual(notifications.active, reminder)
        // Stage 12: both wait underneath (volume coalesced to one) with their own deadlines,
        // and the reminder's deadline is not reset by them.
        XCTAssertEqual(activities.queueCount, 2)
        await drain()
        await clock.waitForPendingSleeps()
        XCTAssertEqual(notifications.expiresAt, base.addingTimeInterval(10))
        await clock.advance(by: .milliseconds(2500))
        await drain()
        XCTAssertEqual(notifications.active, reminder)
        XCTAssertEqual(activities.queueCount, 0)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(1500))
        await drain()
        XCTAssertNil(notifications.active)
        XCTAssertNil(activities.activeTransient)
        let sleepers = await clock.pendingSleepCount()
        XCTAssertEqual(sleepers, 0)
    }

    func testVolumeAndMuteCoalesceWithStableIdentityAndExtendDeadline() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let notifications = activities.notifications
        notifications.present(audio())
        let id = notifications.active?.id
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(1))
        for level in [0.54, 0.58, 0.62] { notifications.present(audio(level)) }
        notifications.present(audio(0.62, muted: true))
        XCTAssertEqual(notifications.active?.id, id)
        XCTAssertEqual(notifications.active?.kind, .mute)
        notifications.present(audio(0.62))
        XCTAssertEqual(notifications.active?.id, id)
        XCTAssertEqual(notifications.active?.kind, .volume)
        XCTAssertEqual(activities.queueCount, 0)
        await drain()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(300))
        await drain()
        XCTAssertNotNil(notifications.active)
        await clock.advance(by: .milliseconds(1450))
        await drain()
        XCTAssertNil(notifications.active)
    }

    func testHoverDoesNotChangeAbsoluteExpiry() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let notifications = activities.notifications
        notifications.present(calendar())
        await clock.waitForPendingSleeps()
        let deadline = notifications.expiresAt
        XCTAssertEqual(deadline, base.addingTimeInterval(10))
        await clock.advance(by: .seconds(4))
        notifications.setHovered(true)
        XCTAssertEqual(notifications.expiresAt, deadline)
        await clock.advance(by: .seconds(6))
        await drain()
        XCTAssertNil(notifications.active)
        notifications.setHovered(false)
        XCTAssertNil(notifications.active)
    }

    func testDefaultDurations() {
        for kind in [NotchNotification.Kind.reminder60, .reminder30, .reminder5] {
            XCTAssertEqual(kind.defaultDuration, .seconds(5))
        }
        XCTAssertEqual(audio(output: true).duration, .milliseconds(2500))
        XCTAssertEqual(audio().duration, .milliseconds(1750))
        XCTAssertEqual(audio(muted: true).duration, .milliseconds(1750))
    }

    func testUnchangedAudioSnapshotDoesNotExtendExpiry() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let notifications = activities.notifications
        notifications.present(audio())
        await clock.waitForPendingSleeps()
        let deadline = notifications.expiresAt
        await clock.advance(by: .seconds(1))
        notifications.present(audio())
        XCTAssertEqual(notifications.expiresAt, deadline)
        await clock.advance(by: .milliseconds(750))
        await drain()
        XCTAssertNil(notifications.active)
    }

    func testCalendarRemindersKeepDiscreteIdentities() {
        let activities = ActivityCoordinator(clock: TestAppClock(now: base, automaticallyAdvances: false))
        activities.notifications.present(calendar())
        let firstID = activities.notifications.active?.id
        activities.notifications.present(calendar())
        XCTAssertNotEqual(activities.notifications.active?.id, firstID)
        activities.clearAll()
    }

    func testGlobalPreemptionAndResetDoNotReplayStaleNotifications() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        activities.notifications.present(calendar())
        activities.present(.init(id: UUID(), kind: .notification, title: "Critical", subtitle: nil,
                                 priority: .critical, duration: nil))
        XCTAssertNil(activities.notifications.active)
        // Stage 12: the interrupted reminder waits underneath on its original deadline.
        XCTAssertEqual(activities.queueCount, 1)
        await drain()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(10))
        await drain()
        XCTAssertEqual(activities.queueCount, 0)
        activities.dismissActive()
        XCTAssertNil(activities.activeTransient)
        XCTAssertNil(activities.notifications.active)
        activities.notifications.present(audio())
        activities.clearAll()
        await drain()
        XCTAssertNil(activities.notifications.active)
        let sleepers = await clock.pendingSleepCount()
        XCTAssertEqual(sleepers, 0)
    }

    func testReplacementHasNoIntermediateEmptyActivityAndDismissalCanReverse() {
        let activities = ActivityCoordinator(clock: TestAppClock(now: base, automaticallyAdvances: false))
        activities.notifications.present(audio())
        var values: [NotchActivity?] = []
        let observation = activities.$activeTransient.sink { values.append($0) }
        activities.notifications.present(calendar())
        XCTAssertFalse(values.contains(where: { $0 == nil }))
        activities.notifications.dismissByUser()
        activities.notifications.present(audio(output: true))
        XCTAssertEqual(activities.notifications.active?.kind, .outputDeviceChanged)
        // The unexpired volume activity is still live underneath the output change.
        XCTAssertEqual(activities.queueCount, 1)
        observation.cancel()
        activities.clearAll()
    }

    func testCalendarJoinDispatchesReminderURLAndDismissesSharedSlot() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        var opened: [URL] = []
        let calendar = CalendarActivityModel(service: MockCalendarService(), coordinator: activities,
            clock: clock, openMeeting: { opened.append($0) })
        let url = URL(string: "https://meet.google.com/abc-defg-hij")!
        await calendar.reminders.update(events: [.init(id: UUID(), title: "Meeting",
            startDate: base.addingTimeInterval(300), endDate: base.addingTimeInterval(3600), meetingURL: url)])
        XCTAssertEqual(activities.notifications.active?.action, .join(url))
        calendar.joinReminder()
        XCTAssertEqual(opened, [url])
        XCTAssertNil(activities.notifications.active)
        XCTAssertNil(activities.activeTransient)
        XCTAssertNil(calendar.reminders.current)
        calendar.reminders.stop()
    }

    func testOutputNotificationDoesNotBorrowItsPriorityForLaterVolumeUpdates() {
        let activities = ActivityCoordinator(clock: TestAppClock(now: base, automaticallyAdvances: false))
        let notifications = activities.notifications
        notifications.present(audio(output: true))
        XCTAssertFalse(notifications.present(audio(0.7)))
        XCTAssertEqual(notifications.active?.kind, .outputDeviceChanged)
        notifications.dismiss()
        notifications.present(audio(0.7))
        XCTAssertEqual(notifications.active?.priority, .low)
        notifications.present(calendar(priority: .medium))
        XCTAssertEqual(notifications.active?.kind, .reminder30)
        XCTAssertFalse(notifications.present(audio(0.8)))
        activities.clearAll()
    }

    func testNotificationRevealsBeforeSettlingAndReplacementStaysVisible() {
        let passive = NotchShape(width: 212, height: 38, centerX: 300, topCornerRadius: 0, bottomCornerRadius: 8)
        var surface = NotchSurfaceFrame(shape: NotchShellSurface(width: 356, height: 103, centerX: 300,
            bottomRadius: 34, passiveShape: passive), phase: .openingBlack, expandedHeight: 126,
            notificationVisible: true) { _ in Color.clear }
        XCTAssertEqual(surface.contentPhase, .openingBlack)
        surface.shape.height = 104
        XCTAssertEqual(surface.contentPhase, .collapsed)
        var closing = NotchSurfaceFrame(shape: surface.shape, phase: .closingBlack,
            expandedHeight: 126, notificationVisible: true) { _ in Color.clear }
        XCTAssertEqual(closing.contentPhase, .closingBlack)
        closing.keepsNotificationContent = true
        XCTAssertEqual(closing.contentPhase, .collapsed)
    }

    func testUnifiedGeometryIsTopAttachedRoundedAndMatchesPointerFrame() {
        let layout = NotchGeometryResolver.layout(for: .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        for style in [NotchNotification.PresentationStyle.calendar, .feedback] {
            let size = NotchNotificationGeometry.size(for: style, layout: layout)
            let frame = NotchNotificationGeometry.frame(for: style, layout: layout)
            XCTAssertEqual(frame.size, size)
            XCTAssertEqual(frame.maxY, layout.collapsedVisibleFrame.maxY)
            let shape = NotchShellSurface(width: size.width, height: size.height, centerX: 370, bottomRadius: 34,
                passiveShape: NotchShape(width: 212, height: 38, centerX: 370, topCornerRadius: 0, bottomCornerRadius: 8), shoulderRadius: 12)
            let path = shape.path(in: CGRect(x: 0, y: 0, width: 740, height: 322))
            var subpaths = 0
            path.forEach { if case .move = $0 { subpaths += 1 } }
            XCTAssertEqual(subpaths, 1)
            XCTAssertTrue(path.contains(CGPoint(x: 370, y: 37)))
            XCTAssertTrue(path.contains(CGPoint(x: 370, y: 39)))
            XCTAssertFalse(path.contains(CGPoint(x: 370 - size.width / 2 + 14, y: size.height - 2)))
        }
    }
}
