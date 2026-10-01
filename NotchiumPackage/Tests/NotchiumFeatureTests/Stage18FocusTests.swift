import Foundation
import NotchiumCore
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumFocusFeature
@testable import NotchiumServices
@testable import NotchiumShelfFeature

@MainActor
final class Stage18FocusTests: XCTestCase {
    private let focusKey = NotchActivityKey("focus.mode")

    func testFocusChangesAnnounceOnceAndTheFirstAnswerIsSilent() async {
        let (model, activities, service) = make()
        model.start()
        await waitUntil { model.isFocused == false }
        XCTAssertNil(activities.notifications.active, "Launch state is not a change")

        service.send(isFocused: true)
        await waitUntil { model.isFocused == true }
        let on = activities.notifications.active
        XCTAssertEqual(on?.kind, .focusModeChanged)
        XCTAssertEqual(on?.presentationStyle, .compact)
        XCTAssertEqual(on?.content.compactActivity?.glyph, .symbol("moon.fill"))
        XCTAssertTrue(activities.reducesInterruptions)

        service.send(isFocused: false)
        await waitUntil { model.isFocused == false }
        XCTAssertEqual(activities.notifications.active?.id, on?.id, "On → Off updates one activity in place")
        XCTAssertEqual(activities.notifications.active?.content.compactActivity?.trailing, .text("Focus Off"))
        XCTAssertEqual(activities.liveActivities.filter { $0.key == focusKey }.count, 1)
        XCTAssertFalse(activities.reducesInterruptions)
        model.stop()
    }

    func testFocusQuietsRoutineEventsButNotImportantOnes() {
        let (model, activities, _) = make()
        model.receive(FocusSnapshot(availability: .available, isFocused: false))
        model.receive(FocusSnapshot(availability: .available, isFocused: true))
        activities.dismiss(key: focusKey)

        for quiet in [notification(.screenshot, key: "screenshot"), notification(.outputDeviceChanged, key: "audio.output"),
                      notification(.charging, key: "battery"), notification(.reminder30, key: "calendar.a")] {
            XCTAssertFalse(activities.notifications.present(quiet), "\(quiet.kind) stays quiet during Focus")
            XCTAssertFalse(activities.liveActivities.contains { $0.key.rawValue == quiet.coalescingKey })
        }
        for important in [notification(.criticalBattery, key: "battery"), notification(.reminder5, key: "calendar.b"),
                          notification(.focusTimerComplete, key: "pomodoro.result"),
                          notification(.transferFailed, key: "transfer"), notification(.volume, key: "audio.level"),
                          notification(.shelfAdded, key: "shelf.added")] {
            activities.notifications.present(important)
            XCTAssertTrue(activities.liveActivities.contains { $0.key.rawValue == important.coalescingKey },
                          "\(important.kind) still presents")
            activities.dismiss(key: NotchActivityKey(important.coalescingKey))
        }

        model.reducesInterruptions = false
        XCTAssertTrue(activities.notifications.present(notification(.screenshot, key: "screenshot")))
    }

    func testFocusNeverChangesThePage() async {
        let presentation = DynamicIslandPresentationModel(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { presentation.reset() }
        let service = MockFocusService()
        let model = FocusModeModel(service: service, activities: presentation.activityCoordinator,
                                   shortcuts: MockShortcutService(), preferences: defaults())
        presentation.present(.expanded, animated: false)
        presentation.pageModel.selectedPage = .audio
        model.start()
        await waitUntil { model.isFocused == false }
        service.send(isFocused: true)
        await waitUntil { model.isFocused == true }
        XCTAssertEqual(presentation.pageModel.selectedPage, .audio)
        XCTAssertEqual(presentation.visualState, .expanded)
        model.stop()
    }

    func testTimerFocusSessionsRunTheUsersShortcutsOnlyForFocusItTurnedOn() async {
        let on = ExistingShortcut(id: UUID(), name: "Focus On")
        let off = ExistingShortcut(id: UUID(), name: "Focus Off")
        let shortcuts = MockShortcutService(shortcuts: [on, off])
        let activities = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { activities.clearAll() }
        let model = FocusModeModel(service: MockFocusService(), activities: activities, shortcuts: shortcuts,
                                   preferences: defaults())
        model.receive(FocusSnapshot(availability: .available, isFocused: false))

        model.focusSessionBegan()
        XCTAssertFalse(model.turnedOnByTimer, "Off by default: the timer works without Focus control")

        model.timerControlsFocus = true
        model.focusOnShortcut = on
        model.focusOffShortcut = off
        model.focusSessionBegan()
        model.focusSessionEnded()
        await waitForExecutions(shortcuts, count: 2)
        let executed = await shortcuts.executions
        XCTAssertEqual(executed, [on, off])

        model.receive(FocusSnapshot(availability: .available, isFocused: true))
        model.focusSessionBegan()
        model.focusSessionEnded()
        try? await Task.sleep(for: .milliseconds(50))
        let unchanged = await shortcuts.executions
        XCTAssertEqual(unchanged, [on, off], "A Focus the user turned on is left alone")
    }

    func testRepeatedPollsOfTheSameStateNeverReannounce() async {
        let (model, activities, service) = make()
        model.start()
        await waitUntil { model.isFocused == false }
        service.send(isFocused: true)
        await waitUntil { model.isFocused == true }
        let first = activities.notifications.active
        activities.dismiss(key: focusKey)
        service.send(isFocused: true)
        service.send(isFocused: true)
        await drainMainActorTasks()
        XCTAssertNotNil(first)
        XCTAssertFalse(activities.liveActivities.contains { $0.key == focusKey }, "Same state, no new activity")
        model.stop()
    }

    func testFocusKeepsScreenshotsInTheShelfButOffTheNotch() {
        let (model, activities, _) = make()
        let screenshots = ScreenshotActivityModel(activities: activities)
        model.receive(FocusSnapshot(availability: .available, isFocused: false))
        model.receive(FocusSnapshot(availability: .available, isFocused: true))
        activities.dismiss(key: focusKey)

        let during = ScreenshotCapture(fileURL: URL(fileURLWithPath: "/tmp/Shot 1.png"), createdAt: Date(timeIntervalSince1970: 1))
        screenshots.receive(.captured(during))
        XCTAssertEqual(screenshots.recent.map(\.id), [during.id], "Detected and kept for the Shelf")
        XCTAssertNil(activities.notifications.active, "No screenshot activity during Focus")
        XCTAssertFalse(activities.liveActivities.contains { $0.kind == .screenshot })

        model.receive(FocusSnapshot(availability: .available, isFocused: false))
        activities.dismiss(key: focusKey)
        let after = ScreenshotCapture(fileURL: URL(fileURLWithPath: "/tmp/Shot 2.png"), createdAt: Date(timeIntervalSince1970: 2))
        screenshots.receive(.captured(after))
        XCTAssertEqual(activities.notifications.active?.kind, .screenshot, "After Focus, screenshots present again")
        XCTAssertEqual(screenshots.recent.count, 2)
    }

    func testAnUnentitledBuildReportsFocusUnavailableInsteadOfAConstantOff() async {
        let activities = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { activities.clearAll() }
        let service = RealFocusService(isEntitled: false)
        let availability = await service.availability()
        XCTAssertEqual(availability, .unavailable(.unsupportedDistribution))
        let model = FocusModeModel(service: service, activities: activities, shortcuts: MockShortcutService(),
                                   preferences: defaults())
        model.start()
        await waitUntil { model.availability == .unavailable(.unsupportedDistribution) }
        XCTAssertNil(model.isFocused, "No fabricated Focus state")
        XCTAssertFalse(activities.reducesInterruptions)
        XCTAssertNil(activities.notifications.active)
        model.stop()
    }

    // MARK: Helpers

    private func make() -> (FocusModeModel, ActivityCoordinator, MockFocusService) {
        let activities = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        addTeardownBlock { @MainActor in activities.clearAll() }
        let service = MockFocusService()
        let model = FocusModeModel(service: service, activities: activities, shortcuts: MockShortcutService(),
                                   preferences: defaults())
        return (model, activities, service)
    }

    private func notification(_ kind: NotchNotification.Kind, key: String) -> NotchNotification {
        NotchNotification(kind: kind, coalescingKey: key, action: .none, presentationStyle: .compact,
                          content: .compact(.init(glyph: .symbol("circle"), title: "\(kind)", trailing: .text("x"))))
    }

    private func defaults() -> UserDefaults {
        let name = "notchium.tests.focus.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func waitForExecutions(_ service: MockShortcutService, count: Int) async {
        for _ in 0..<200 {
            if await service.executions.count >= count { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
