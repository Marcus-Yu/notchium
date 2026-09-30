import AppKit
import Combine
import Foundation
import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class Stage10CoordinationTests: XCTestCase {
    private func clock() -> TestAppClock {
        TestAppClock(now: Date(timeIntervalSince1970: 1_800_000_000), automaticallyAdvances: false)
    }

    private func reminder(_ kind: NotchNotification.Kind = .reminder5, key: String = "event") -> NotchNotification {
        .init(kind: kind, duration: .seconds(10), coalescingKey: key,
              action: .calendar, presentationStyle: .calendar,
              content: .calendar(title: "Meeting", status: "5 min"))
    }

    private func audio() -> NotchNotification {
        .audio(.init(kind: .volume, deviceName: "Speakers", volume: 0.5, isMuted: false))
    }

    private func drain() async { for _ in 0..<100 { await Task.yield() } }

    func testSemanticPriorityTable() {
        XCTAssertEqual(ActivityPriorityPolicy.priority(for: NotchNotification.Kind.reminder5), .high)
        for kind in [NotchNotification.Kind.reminder30, .reminder60, .outputDeviceChanged] {
            XCTAssertEqual(ActivityPriorityPolicy.priority(for: kind), .medium)
        }
        for kind in [NotchNotification.Kind.volume, .mute] {
            XCTAssertEqual(ActivityPriorityPolicy.priority(for: kind), .low)
        }
    }

    func testPersistentIdentitySurvivesAudioCalendarReplacementAndDismissal() {
        let activities = ActivityCoordinator(clock: clock())
        let music = NotchActivity(id: UUID(), kind: .media, title: "Track", subtitle: nil,
                                  duration: nil, payload: .mediaPlayback(isPlaying: true))
        activities.present(music)
        var persistentChanges = 0
        let observation = activities.$persistentActivity.dropFirst().sink { _ in persistentChanges += 1 }
        defer { observation.cancel(); activities.clearAll() }
        for notification in [audio(), reminder()] {
            XCTAssertTrue(activities.notifications.present(notification))
            XCTAssertEqual(activities.foregroundActivity?.id, notification.id)
            XCTAssertEqual(activities.underlyingActivity, music)
            XCTAssertEqual(activities.presentationMode, .combined)
            XCTAssertTrue(activities.retainsMediaPresentation)
        }
        XCTAssertFalse(activities.notifications.present(audio()))
        activities.notifications.dismissByUser()
        // Stage 12: the interrupted, unexpired volume resumes before Music.
        XCTAssertEqual(activities.foregroundActivity?.kind, .systemHUD)
        activities.notifications.dismissByUser()
        XCTAssertEqual(activities.foregroundActivity, music)
        XCTAssertNil(activities.transientActivity)
        XCTAssertEqual(persistentChanges, 0)
        XCTAssertEqual(activities.preferredExpandedPage, .music)
    }

    func testEveryManualPageSurvivesNotificationReplacementAndExpiry() async {
        for page in NotchPage.allCases {
            let clock = clock()
            let model = DynamicIslandPresentationModel(clock: clock)
            model.present(.expanded, animated: false)
            model.pageModel.selectedPage = page
            var selections: [NotchPage] = []
            let observation = model.pageModel.$selectedPage.dropFirst().sink { selections.append($0) }
            model.notificationCoordinator.present(audio())
            model.notificationCoordinator.present(reminder())
            await clock.waitForPendingSleeps()
            await clock.advance(by: .seconds(10))
            await drain()
            XCTAssertNil(model.notificationCoordinator.active)
            XCTAssertEqual(model.pageModel.selectedPage, page)
            XCTAssertTrue(selections.isEmpty)
            observation.cancel()
            model.present(.collapsed, animated: false) // Complete collapse before a fresh expansion.
            model.setExpanded(true)
            XCTAssertEqual(model.pageModel.selectedPage, .home)
            model.reset()
        }
    }

    func testDragDoesNotExtendNotificationLifetime() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        let notification = reminder()
        let coordinator = activities.notifications
        coordinator.present(notification)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(4))
        coordinator.setHovered(true)
        coordinator.setInteracting(true, id: notification.id)
        coordinator.setHovered(false)
        await clock.advance(by: .seconds(6))
        await drain()
        XCTAssertNil(coordinator.active)
        coordinator.setInteracting(false, id: notification.id)
        XCTAssertNil(coordinator.active)
        let pending = await clock.pendingSleepCount()
        XCTAssertEqual(pending, 0)
    }

    func testReplacedNotificationIgnoresStaleDragCompletion() {
        let activities = ActivityCoordinator(clock: clock())
        let old = reminder(.reminder30, key: "old")
        let new = reminder(key: "new")
        activities.notifications.present(old)
        activities.notifications.setInteracting(true, id: old.id)
        activities.notifications.present(new)
        activities.notifications.dismissByUser(id: old.id)
        activities.notifications.setInteracting(false, id: old.id)
        XCTAssertEqual(activities.notifications.active, new)
        XCTAssertNil(activities.notifications.interactingID)
        activities.clearAll()
    }

    func testNestedAuxiliaryInteractionsRetainHoverUntilLastChildCloses() async {
        let clock = clock()
        let model = DynamicIslandPresentationModel(clock: clock)
        model.present(.hovered, animated: false)
        model.setAuxiliaryInteractionPresented(true, source: "picker")
        model.setAuxiliaryInteractionPresented(true, source: "menu")
        model.setHovered(false)
        model.setAuxiliaryInteractionPresented(false, source: "menu")
        model.handleEscape()
        await clock.advance(by: .seconds(1))
        await drain()
        XCTAssertTrue(model.isAuxiliaryInteractionPresented)
        XCTAssertEqual(model.visualState, .hovered)
        model.setAuxiliaryInteractionPresented(false, source: "picker")
        await drain()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(200))
        await drain()
        XCTAssertEqual(model.visualState, .collapsed)
        model.reset()
    }

    func testEscapeCollapsesExpandedShellWithoutExtendingHiddenNotification() {
        let model = DynamicIslandPresentationModel(clock: clock())
        model.present(.expanded, animated: false)
        model.notificationCoordinator.present(reminder())
        model.handleEscape()
        XCTAssertNotNil(model.notificationCoordinator.active)
        XCTAssertEqual(model.visualState, .collapsed)
        model.handleEscape()
        XCTAssertNil(model.notificationCoordinator.active)
        model.reset()
    }

    func testPendingHoverExpandsDespiteNewNotification() async {
        let clock = clock()
        let model = DynamicIslandPresentationModel(clock: clock)
        model.setHovered(true)
        await clock.waitForPendingSleeps()
        model.notificationCoordinator.present(reminder())
        await clock.advance(by: .milliseconds(120))
        await drain()
        XCTAssertEqual(model.visualState, .hovered)
        XCTAssertNotNil(model.notificationCoordinator.active)
        model.reset()
    }

    func testIdleCoordinatorHasNoScheduledWorkAfterReset() async {
        let clock = clock()
        let model = DynamicIslandPresentationModel(clock: clock)
        model.notificationCoordinator.present(audio())
        await clock.waitForPendingSleeps()
        model.reset()
        await drain()
        let pending = await clock.pendingSleepCount()
        XCTAssertEqual(pending, 0)
    }

    func testNativeMenuTrackingRetainsShellAndEscapeDefersToMenu() {
        let model = DynamicIslandPresentationModel(clock: clock())
        let controller = NotchiumPanelController(model: model)
        model.present(.expanded, animated: false)
        let menu = NSMenu()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        XCTAssertTrue(model.isAuxiliaryInteractionPresented)
        controller.handleEscapeCommand()
        XCTAssertEqual(model.visualState, .expanded)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        controller.handleEscapeCommand()
        XCTAssertEqual(model.visualState, .collapsed)
        model.reset()
    }

    func testLowerPrioritySameFamilyCannotReplaceUrgentCalendarOrOutput() {
        for kinds in [(NotchActivityKind.meeting, NotchActivityKind.calendar), (.audioDevice, .systemHUD)] {
            let activities = ActivityCoordinator(clock: clock())
            let urgent = NotchActivity(id: UUID(), kind: kinds.0, title: "Foreground", subtitle: nil,
                                       duration: .seconds(10))
            let lower = NotchActivity(id: UUID(), kind: kinds.1, title: "Lower", subtitle: nil,
                                      duration: .seconds(1))
            activities.present(urgent)
            activities.present(lower)
            XCTAssertEqual(activities.foregroundActivity, urgent)
            // Stage 12: lower priority waits underneath instead of being discarded.
            XCTAssertEqual(activities.queueCount, 1)
            activities.clearAll()
        }
    }

    func testExpandedNotificationPointerFrameUsesFixedShellAndExistingContentHeight() {
        let layout = NotchGeometryResolver.layout(for: .init(display: NotchShellDebugModel.builtInFixture,
                                                            mode: .physicalNotch), state: .expanded)
        for style in [NotchNotification.PresentationStyle.feedback, .calendar] {
            let frame = NotchNotificationGeometry.interactionFrame(for: style, layout: layout, expanded: true)
            XCTAssertEqual(frame.minY, layout.visibleSurfaceFrame.minY)
            XCTAssertEqual(frame.width, ExpandedNotchLayout.size.width)
            XCTAssertEqual(frame.height, NotchNotificationGeometry.contentHeight(for: style))
            XCTAssertTrue(layout.visibleSurfaceFrame.contains(frame))
        }
    }
}
