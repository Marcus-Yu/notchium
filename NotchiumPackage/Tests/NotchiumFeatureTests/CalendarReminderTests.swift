import Foundation
import NotchiumCore
@testable import NotchiumCalendarFeature
@testable import NotchiumDynamicIsland
import NotchiumServices
import SwiftUI
import XCTest

@MainActor
final class CalendarReminderTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(minutesAway: TimeInterval, meeting: Bool = false) -> CalendarEventSummary {
        let start = base.addingTimeInterval(minutesAway * 60)
        return CalendarEventSummary(id: UUID(), title: "Team meeting", startDate: start,
            endDate: start.addingTimeInterval(1800),
            meetingURL: meeting ? URL(string: "https://meet.google.com/abc-defg-hij") : nil)
    }

    func testThresholdsFireOnceAndRestoreMedia() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let media = NotchActivity(id: UUID(), kind: .media, title: "Playing",
            subtitle: nil, priority: 20, duration: nil)
        activities.present(media)
        let reminders = CalendarReminderCoordinator(activities: activities, clock: clock)
        let upcoming = event(minutesAway: 60)

        await reminders.update(events: [upcoming])
        XCTAssertEqual(reminders.current?.label, "in 1 hr")
        XCTAssertEqual(activities.activeActivity?.kind, .calendar)
        reminders.dismiss()
        XCTAssertEqual(activities.activeActivity, media)
        await reminders.update(events: [upcoming])
        XCTAssertNil(reminders.current)

        await clock.advance(by: .seconds(1800))
        await reminders.update(events: [upcoming])
        XCTAssertEqual(reminders.current?.label, "30 min")
        reminders.dismiss()
        await clock.advance(by: .seconds(1500))
        await reminders.update(events: [upcoming])
        XCTAssertEqual(reminders.current?.label, "5 min")
        reminders.dismiss()
        XCTAssertEqual(activities.activeActivity, media)
        reminders.stop()
    }

    func testWakeShowsOneCurrentReminderAndLaterFiveMinuteReminder() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let reminders = CalendarReminderCoordinator(activities: activities, clock: clock)
        let upcoming = event(minutesAway: 7, meeting: true)
        await reminders.update(events: [upcoming])
        XCTAssertEqual(reminders.current?.label, "7 min")
        XCTAssertFalse(reminders.current?.isImminent ?? true)
        XCTAssertEqual(activities.queueCount, 0)
        reminders.dismiss()
        await reminders.update(events: [upcoming])
        XCTAssertNil(reminders.current)
        await clock.advance(by: .seconds(120))
        await reminders.update(events: [upcoming])
        XCTAssertEqual(reminders.current?.label, "5 min")
        XCTAssertTrue(reminders.current?.isImminent ?? false)
        reminders.dismiss()
        await clock.advance(by: .seconds(300))
        await reminders.update(events: [upcoming])
        XCTAssertEqual(reminders.current?.label, "Now")
        XCTAssertTrue(reminders.current?.isNow ?? false)
        reminders.stop()
    }

    func testSoonestEventWinsAndHigherPriorityActivitySuppressesStaleAlert() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let reminders = CalendarReminderCoordinator(activities: activities, clock: clock)
        let later = event(minutesAway: 20)
        let sooner = event(minutesAway: 7)
        await reminders.update(events: [later, sooner])
        XCTAssertEqual(reminders.current?.event.id, sooner.id)
        XCTAssertEqual(activities.queueCount, 0)
        reminders.dismiss()
        let critical = NotchActivity(id: UUID(), kind: .notification, title: "Critical",
            subtitle: nil, priority: 100, duration: nil)
        activities.present(critical)
        let another = event(minutesAway: 6)
        await reminders.update(events: [another])
        XCTAssertNil(reminders.current)
        XCTAssertEqual(activities.queueCount, 0)
        reminders.stop()
    }

    func testTenSecondDismissalPausesWhileHovered() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let reminders = CalendarReminderCoordinator(activities: activities, clock: clock)
        await reminders.update(events: [event(minutesAway: 5)])
        await clock.waitForPendingSleeps()
        reminders.setHovered(true)
        while await clock.pendingSleepCount() != 0 { await Task.yield() }
        await clock.advance(by: .seconds(20))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNotNil(reminders.current)

        reminders.setHovered(false)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(10))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(reminders.current)
        XCTAssertNil(activities.activeActivity)
        reminders.stop()
    }

    func testNextThresholdUsesScheduledSleep() async {
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let reminders = CalendarReminderCoordinator(activities: activities, clock: clock)
        let upcoming = event(minutesAway: 60 + 1.0 / 60.0)
        await reminders.update(events: [upcoming])
        XCTAssertNil(reminders.current)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(1))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(reminders.current?.label, "in 1 hr")
        reminders.stop()
    }

    func testReminderSharesOneOutlineWithMusicOrIdleNotch() {
        let bounds = CGRect(x: 0, y: 0, width: 740, height: 322)
        let passive = NotchShape(width: 180, height: 38, centerX: 370,
                                 topCornerRadius: 0, bottomCornerRadius: 8,
                                 hardwareExclusion: CGRect(x: 280, y: 0, width: 180, height: 38))

        for topWidth: CGFloat in [260, 180] {
            var surface = NotchShellSurface(width: topWidth, height: 38, centerX: 370,
                                            bottomRadius: 8, passiveShape: passive,
                                            reminderHeight: 70)
            let path = surface.path(in: bounds)
            var subpathCount = 0
            path.forEach { element in
                if case .move = element { subpathCount += 1 }
            }
            XCTAssertEqual(subpathCount, 1)
            XCTAssertTrue(path.contains(CGPoint(x: 370, y: 37)))
            XCTAssertTrue(path.contains(CGPoint(x: 370, y: 39)))
            XCTAssertEqual(path.boundingRect.minX, 370 - topWidth / 2)
            XCTAssertEqual(path.boundingRect.maxX, 370 + topWidth / 2)
            for y: CGFloat in [1, 37, 39, 70, 99] {
                XCTAssertTrue(path.contains(CGPoint(x: 371 - topWidth / 2, y: y)))
                XCTAssertTrue(path.contains(CGPoint(x: 369 + topWidth / 2, y: y)))
                XCTAssertFalse(path.contains(CGPoint(x: 369 - topWidth / 2, y: y)))
                XCTAssertFalse(path.contains(CGPoint(x: 371 + topWidth / 2, y: y)))
            }
            XCTAssertFalse(path.contains(CGPoint(x: 370, y: 109)))

            surface.reminderHeight = 0
            if topWidth == passive.width {
                XCTAssertTrue(surface.path(in: bounds).isEmpty)
            } else {
                XCTAssertTrue(surface.path(in: bounds).contains(CGPoint(x: 370, y: 37)))
            }
        }
    }

    func testReminderOutlineStaysConnectedDuringResizeAndReveal() {
        let bounds = CGRect(x: 0, y: 0, width: 740, height: 322)
        let passive = NotchShape(width: 180, height: 38, centerX: 370,
                                 topCornerRadius: 0, bottomCornerRadius: 8)
        for topWidth: CGFloat in [180, 260, 400] {
            for topHeight: CGFloat in [24, 38, 50] {
                for dropHeight: CGFloat in [0.5, 10, 35, 70] {
                    let surface = NotchShellSurface(
                        width: topWidth, height: topHeight, centerX: 370,
                        bottomRadius: 8, passiveShape: passive,
                        reminderHeight: dropHeight)
                    let path = surface.path(in: bounds)
                    // Side walls stay fixed throughout the reveal; only the
                    // bottom corners move down with the shell's total height.
                    XCTAssertEqual(path.boundingRect.minX, 370 - topWidth / 2)
                    XCTAssertEqual(path.boundingRect.maxX, 370 + topWidth / 2)
                    for y in stride(from: CGFloat(1), through: topHeight + dropHeight - 8, by: 1) {
                        XCTAssertTrue(path.contains(CGPoint(x: 371 - topWidth / 2, y: y)))
                        XCTAssertTrue(path.contains(CGPoint(x: 369 + topWidth / 2, y: y)))
                    }
                    XCTAssertTrue(path.contains(CGPoint(x: 370, y: topHeight - 0.1)))
                    XCTAssertTrue(path.contains(CGPoint(x: 370, y: topHeight + 0.1)))
                    XCTAssertEqual(path.boundingRect.maxY, topHeight + dropHeight)
                }
            }
        }
    }

    func testReminderWideningIsBoundedAndCentered() {
        let layout = NotchGeometryResolver.layout(
            for: NotchShellPlacement(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch),
            state: .collapsed)
        let width = NotchReminderGeometry.width(for: layout)
        XCTAssertEqual(width, 356)
        for height: CGFloat in [44, 60, 80, 96] {
            let frame = NotchReminderGeometry.contentFrame(for: layout, height: height)
            XCTAssertEqual(frame.midX, layout.collapsedVisibleFrame.midX)
            XCTAssertEqual(frame.maxY, layout.collapsedVisibleFrame.minY)
            XCTAssertEqual(frame.height, height)
            XCTAssertEqual(frame.width, width)
        }
    }

    func testReminderRevealWidensBeforeGrowingAndReversesWithoutDetaching() {
        let bounds = CGRect(x: 0, y: 0, width: 740, height: 322)
        let passive = NotchShape(width: 212, height: 38, centerX: 370,
                                 topCornerRadius: 0, bottomCornerRadius: 8)
        for normalWidth: CGFloat in [212, 292] {
            var previousSize = CGSize(width: normalWidth, height: 38)
            for step in 0...60 {
                let progress = CGFloat(step) / 60
                let shape = NotchShellSurface(width: normalWidth, height: 38, centerX: 370,
                    bottomRadius: 8, passiveShape: passive, reminderHeight: 60,
                    reminderWidth: 356, reminderProgress: progress)
                let path = shape.path(in: bounds)
                XCTAssertEqual(path.boundingRect.midX, 370, accuracy: 0.001)
                XCTAssertEqual(path.boundingRect.minY, 0)
                XCTAssertGreaterThanOrEqual(path.boundingRect.width, previousSize.width)
                XCTAssertGreaterThanOrEqual(path.boundingRect.height, previousSize.height)
                if progress <= 0.2 { XCTAssertEqual(path.boundingRect.height, 38) }
                if progress >= 0.55 { XCTAssertEqual(path.boundingRect.width, 356) }
                previousSize = path.boundingRect.size
                var reverse = shape
                reverse.reminderProgress = 1
                // Exercise native interpolation's progress channel on dismissal.
                var data = reverse.animatableData
                data.second.second = progress
                reverse.animatableData = data
                XCTAssertEqual(reverse.path(in: bounds), path)
            }
            XCTAssertEqual(previousSize, CGSize(width: 356, height: 98))
        }
    }

    func testReminderKeepsMusicFlanksWhenPlayingAndWorksWithoutMusic() {
        let model = DynamicIslandPresentationModel(
            clock: TestAppClock(now: base, automaticallyAdvances: false))
        let media = ReminderMediaRenderer()
        model.mediaRenderer = media
        model.calendarRenderer = ReminderCalendarRenderer()
        let playing = NotchActivity(id: UUID(), kind: .media, title: "Playing",
                                    subtitle: nil, priority: 20, duration: nil)
        model.activityCoordinator.present(playing)
        XCTAssertTrue(model.showsCollapsedMedia)

        let reminder = NotchActivity(id: UUID(), kind: .calendar, title: "Meeting",
                                     subtitle: nil, priority: 25, duration: nil)
        model.activityCoordinator.present(reminder)
        XCTAssertTrue(model.showsCalendarReminder)
        XCTAssertTrue(model.showsCollapsedMedia)
        XCTAssertTrue(model.showsSharedMediaArtwork)

        media.collapsedMediaVisible = false
        XCTAssertTrue(model.showsCalendarReminder)
        XCTAssertFalse(model.showsCollapsedMedia)
        XCTAssertFalse(model.showsSharedMediaArtwork)

        media.collapsedMediaVisible = true
        model.activityCoordinator.dismiss(id: reminder.id)
        XCTAssertTrue(model.showsCollapsedMedia)
    }
}

@MainActor
private final class ReminderMediaRenderer: NotchMediaRendering {
    var collapsedMediaVisible = true
    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView {
        AnyView(Color.clear)
    }
    func expandedMedia() -> AnyView { AnyView(Color.clear) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(Color.clear) }
}

@MainActor
private final class ReminderCalendarRenderer: NotchCalendarRendering {
    var reminderVisible = true
    func reminderBanner() -> AnyView { AnyView(Color.clear) }
    func setReminderHovered(_ hovered: Bool) {}
    func expandedCalendar() -> AnyView { AnyView(Color.clear) }
}
