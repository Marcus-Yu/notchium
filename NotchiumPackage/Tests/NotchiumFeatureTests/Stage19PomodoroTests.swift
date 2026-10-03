import Foundation
import NotchiumCore
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumFocusFeature

@MainActor
final class Stage19PomodoroTests: XCTestCase {
    private let config = PomodoroConfiguration.standard
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
    /// Wednesday 2026-09-30 09:00 local.
    private var t0: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 9))! }
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    // MARK: Engine

    func testDefaultsAreThirtyFiveFifteen() {
        XCTAssertEqual(config.duration(of: .focus), 30 * 60)
        XCTAssertEqual(config.duration(of: .shortBreak), 5 * 60)
        XCTAssertEqual(config.duration(of: .longBreak), 15 * 60)
        XCTAssertEqual(config.sessionsPerCycle, 4)
    }

    func testFocusCompletesIntoAShortBreakWaitingForStart() {
        var state = PomodoroState()
        PomodoroEngine.start(&state, configuration: config, at: t0)
        XCTAssertEqual(state.run, .running(endsAt: at(30)))
        XCTAssertTrue(PomodoroEngine.advance(&state, configuration: config, to: at(29.9)).isEmpty)
        let events = PomodoroEngine.advance(&state, configuration: config, to: at(30))
        guard case let .focusCompleted(record, next)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(next, .shortBreak)
        XCTAssertTrue(record.completed)
        XCTAssertEqual(record.focusedDuration, 30 * 60)
        XCTAssertEqual(record.cycleIndex, 1)
        XCTAssertEqual(state.phase, .shortBreak)
        XCTAssertEqual(state.run, .ready)
        XCTAssertTrue(PomodoroEngine.advance(&state, configuration: config, to: at(60)).isEmpty)
        XCTAssertEqual(PomodoroEngine.remaining(state, configuration: config, at: at(60)), 5 * 60)
        PomodoroEngine.start(&state, configuration: config, at: at(60))
        XCTAssertEqual(state.run, .running(endsAt: at(65)), "The full break starts only on user input")
    }

    func testFourFocusSessionsLeadToALongBreakThenANewCycle() {
        var state = PomodoroState()
        var now = t0
        var phases: [PomodoroPhase] = []
        for _ in 0..<4 {
            PomodoroEngine.start(&state, configuration: config, at: now)
            now += config.duration(of: .focus)
            _ = PomodoroEngine.advance(&state, configuration: config, to: now)
            phases.append(state.phase)
            XCTAssertEqual(state.run, .ready, "Every break waits for user input")
            PomodoroEngine.start(&state, configuration: config, at: now)
            now += config.duration(of: state.phase)
            _ = PomodoroEngine.advance(&state, configuration: config, to: now)
            XCTAssertEqual(state.run, .ready, "A finished break leaves the next Focus ready, not running")
        }
        XCTAssertEqual(phases, [.shortBreak, .shortBreak, .shortBreak, .longBreak])
        XCTAssertEqual(state.phase, .focus)
        XCTAssertEqual(state.cyclePosition, 0, "The cycle restarts after the long break")
    }

    func testPauseAndResumeMoveTheDeadlineAndRecordOnlyFocusedTime() {
        var state = PomodoroState()
        PomodoroEngine.start(&state, configuration: config, at: t0)
        PomodoroEngine.pause(&state, at: at(10))
        XCTAssertEqual(state.run, .paused(remaining: 20 * 60))
        XCTAssertTrue(PomodoroEngine.advance(&state, configuration: config, to: at(60)).isEmpty, "Paused never completes")
        PomodoroEngine.resume(&state, at: at(60))
        XCTAssertEqual(state.run, .running(endsAt: at(80)))
        let events = PomodoroEngine.advance(&state, configuration: config, to: at(80))
        guard case let .focusCompleted(record, _)? = events.first else { return XCTFail() }
        XCTAssertEqual(record.focusedDuration, 30 * 60)
        XCTAssertEqual(record.segments.count, 2)
    }

    func testSkipFocusRecordsAnInterruptionAndReadiesTheBreak() {
        var state = PomodoroState()
        PomodoroEngine.start(&state, configuration: config, at: t0)
        let events = PomodoroEngine.skip(&state, configuration: config, at: at(12))
        guard case let .focusInterrupted(record?)? = events.first else { return XCTFail("\(events)") }
        XCTAssertFalse(record.completed)
        XCTAssertEqual(record.focusedDuration, 12 * 60)
        XCTAssertEqual(state.phase, .shortBreak)
        XCTAssertEqual(state.run, .ready)
        PomodoroEngine.start(&state, configuration: config, at: at(12))
        XCTAssertTrue(PomodoroEngine.skip(&state, configuration: config, at: at(13)).isEmpty)
        XCTAssertEqual(state.phase, .focus)
        XCTAssertEqual(state.run, .ready)
        XCTAssertEqual(state.cyclePosition, 1)
    }

    func testEndResetsTheCycleAndDropsAccidentalSessions() {
        var state = PomodoroState()
        PomodoroEngine.start(&state, configuration: config, at: t0)
        let accidental = PomodoroEngine.end(&state, at: t0.addingTimeInterval(20))
        XCTAssertEqual(accidental, [.focusInterrupted(nil)], "Under a minute is not history")
        XCTAssertEqual(state, PomodoroState())
        PomodoroEngine.start(&state, configuration: config, at: t0)
        guard case let .focusInterrupted(record?)? = PomodoroEngine.end(&state, at: at(5)).first else { return XCTFail() }
        XCTAssertEqual(record.focusedDuration, 5 * 60)
        XCTAssertEqual(state, PomodoroState())
    }

    func testDeadlineAccuracyIsDerivedFromTheClock() {
        var state = PomodoroState()
        PomodoroEngine.start(&state, configuration: config, at: t0)
        XCTAssertEqual(PomodoroEngine.remaining(state, configuration: config, at: at(5.5)), 24.5 * 60, accuracy: 0.001)
        XCTAssertEqual(PomodoroEngine.remaining(state, configuration: config, at: at(31)), 0)
        XCTAssertEqual(NotchCountdown.label(24 * 60 + 17.2), "24:18", "Rounds up: 00:00 only at the end")
        XCTAssertEqual(NotchCountdown.label(0), "00:00")
    }

    func testSleepWakeCatchUpCompletesOnlyTheStartedFocus() {
        var state = PomodoroState()
        PomodoroEngine.start(&state, configuration: config, at: t0)
        let events = PomodoroEngine.advance(&state, configuration: config, to: at(120))
        XCTAssertEqual(events.count, 1)
        guard case let .focusCompleted(record, _) = events[0] else { return XCTFail() }
        XCTAssertEqual(record.end, at(30))
        XCTAssertEqual(state.phase, .shortBreak)
        XCTAssertEqual(state.run, .ready, "Time away never starts or completes an unstarted stage")
    }

    // MARK: Statistics

    func testTodayCountsFocusOnlyAndCompletedSessions() {
        let records = [record(start: at(0), minutes: 30), record(start: at(60), minutes: 20, completed: false)]
        let stats = PomodoroStatistics(records: records, openSegments: [DateInterval(start: at(120), duration: 600)],
                                       now: at(130), calendar: calendar)
        XCTAssertEqual(stats.todayFocus, (30 + 20 + 10) * 60, "Interrupted and running focus count as time")
        XCTAssertEqual(stats.todaySessions, 1, "Only completed sessions count")
        XCTAssertEqual(stats.totalSessions, 1)
        XCTAssertEqual(stats.totalFocus, 60 * 60)
        XCTAssertEqual(PomodoroStatistics.duration(stats.todayFocus), "1h 0m")
    }

    func testMidnightSplitsFocusTimeAndCountsTheSessionOnItsEndDay() {
        let lateStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 23, minute: 50))!
        let stats = PomodoroStatistics(records: [record(start: lateStart, minutes: 30)],
                                       now: calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 8))!,
                                       calendar: calendar)
        XCTAssertEqual(stats.todayFocus, 20 * 60)
        XCTAssertEqual(stats.days[28].focus, 10 * 60, "Yesterday keeps its 10 minutes")
        XCTAssertEqual(stats.todaySessions, 1)
        XCTAssertEqual(stats.days[28].sessions, 0)
    }

    func testStreakCountsConsecutiveDaysAndResetsAfterAMissedDay() {
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: t0)! }
        let three = [record(start: day(0), minutes: 30), record(start: day(-1), minutes: 30),
                     record(start: day(-2), minutes: 30), record(start: day(-4), minutes: 30)]
        XCTAssertEqual(PomodoroStatistics(records: three, now: t0, calendar: calendar).streak, 3)
        let yesterdayOnly = [record(start: day(-1), minutes: 30), record(start: day(-2), minutes: 30)]
        XCTAssertEqual(PomodoroStatistics(records: yesterdayOnly, now: t0, calendar: calendar).streak, 2,
                       "Today without a session yet keeps yesterday's streak alive")
        let missed = [record(start: day(-2), minutes: 30)]
        XCTAssertEqual(PomodoroStatistics(records: missed, now: t0, calendar: calendar).streak, 0)
        let interruptedOnly = [record(start: day(0), minutes: 25, completed: false)]
        XCTAssertEqual(PomodoroStatistics(records: interruptedOnly, now: t0, calendar: calendar).streak, 0)
    }

    func testThirtyDayHistoryEndsTodayAndLifetimeTotalsUseEveryRecord() {
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: t0)! }
        let records = [record(start: day(-45), minutes: 30), record(start: day(-29), minutes: 30),
                       record(start: day(-3), minutes: 30), record(start: day(-3).addingTimeInterval(3600), minutes: 30)]
        let stats = PomodoroStatistics(records: records, now: t0, calendar: calendar)
        XCTAssertEqual(stats.days.count, 30)
        XCTAssertEqual(stats.days.last?.date, calendar.startOfDay(for: t0))
        XCTAssertEqual(stats.days.first?.date, calendar.startOfDay(for: day(-29)))
        XCTAssertEqual(stats.days[0].focus, 30 * 60)
        XCTAssertEqual(stats.days[26].focus, 60 * 60)
        XCTAssertEqual(stats.days[26].sessions, 2)
        XCTAssertEqual(stats.totalSessions, 4, "Lifetime includes days outside the 30-day window")
        XCTAssertEqual(stats.totalFocus, 120 * 60)
    }

    // MARK: Model, persistence, activities

    func testRelaunchRestoresTheRunningTimerAndCatchesUpSilently() {
        let store = InMemoryPomodoroStore()
        let clock = TestAppClock(now: t0, automaticallyAdvances: false)
        var now = t0
        let first = model(store: store, clock: clock, now: { now })
        first.startTimer()
        now = at(10)
        first.pause()
        first.resume()
        first.stop()

        now = at(10.5)
        let relaunched = model(store: store, clock: clock, now: { now })
        XCTAssertEqual(relaunched.state, first.state, "Phase, deadline and the open session survive relaunch")
        now = at(200)
        relaunched.refresh()
        XCTAssertEqual(relaunched.records.count, 1)
        XCTAssertTrue(relaunched.records[0].completed)
        XCTAssertEqual(relaunched.state.phase, .shortBreak)
        XCTAssertEqual(relaunched.state.run, .ready)
        XCTAssertNil(relaunched.activities.notifications.active, "A completion hours ago is history, not an announcement")
        XCTAssertEqual(store.load().records.count, 1)
    }

    func testCompletionAnnouncesAndTheBreakWaitsForUserInput() {
        let clock = TestAppClock(now: t0, automaticallyAdvances: false)
        var now = t0
        let timer = model(clock: clock, now: { now })
        timer.startTimer()
        let id = timer.activities.notifications.active?.id
        XCTAssertEqual(timer.activities.notifications.active?.kind, .focusTimer)
        now = at(30)
        timer.refresh()
        let result = timer.activities.notifications.active
        XCTAssertEqual(result?.kind, .focusTimerComplete)
        XCTAssertEqual(result?.content, .pomodoroCompletion(title: "Focus Complete"))
        XCTAssertEqual(result?.presentationStyle, .pomodoroCompletion)
        XCTAssertEqual(result?.lifetime, .transient)
        XCTAssertEqual(result?.duration, .seconds(20))
        let live = timer.activities.liveActivities.first { $0.key == NotchActivityKey(PomodoroModel.activityKey) }
        XCTAssertNil(live, "A ready break has no running countdown activity")
        XCTAssertEqual(timer.state.run, .ready)
        timer.activities.dismiss(key: NotchActivityKey(PomodoroModel.resultKey))
        now = at(60)
        timer.refresh()
        XCTAssertNil(timer.activities.notifications.active)
        XCTAssertEqual(timer.countdown().remaining(at: now), 300)
        timer.primaryAction()
        XCTAssertEqual(timer.activities.notifications.active?.id, id, "Starting the break reuses the timer identity")
        XCTAssertEqual(timer.activities.notifications.active?.content.compactActivity?.trailing,
                       .countdown(.running(total: 300, endsAt: at(65))))
        now = at(65)
        timer.refresh()
        XCTAssertEqual(timer.state.phase, .focus)
        XCTAssertEqual(timer.state.run, .ready)
        now = at(90)
        timer.primaryAction()
        XCTAssertEqual(timer.state.run, .running(endsAt: at(120)))
    }

    func testTimerPreferenceBlendsWithVisibleMusicAndMusicPreferenceMakesTheTimerTheChip() {
        let timer = model()
        timer.activities.present(music(visible: true))
        timer.startTimer()
        let id = timer.activities.notifications.active?.id
        let deadline = timer.state.run
        XCTAssertEqual(timer.activities.primary?.key, NotchActivityKey(PomodoroModel.activityKey))
        XCTAssertEqual(timer.activities.notifications.active?.content.compactActivity?.blendsWithMedia, true)
        XCTAssertNil(timer.activities.secondary, "Music already shows inside the timer; no duplicate chip")

        timer.collapsedPreference = .music
        XCTAssertEqual(timer.activities.primary?.key, .media)
        XCTAssertEqual(timer.activities.secondary?.key, NotchActivityKey(PomodoroModel.activityKey))
        guard case .countdown? = timer.activities.secondary?.minimal else { return XCTFail("timer chip is a countdown ring") }
        XCTAssertEqual(timer.activities.liveActivities.first { $0.key.rawValue == PomodoroModel.activityKey }?.id, id,
                       "Changing preference keeps the activity identity")
        XCTAssertEqual(timer.state.run, deadline, "…and never restarts the timer")

        timer.activities.present(music(visible: false))
        XCTAssertEqual(timer.activities.primary?.key, NotchActivityKey(PomodoroModel.activityKey),
                       "Paused Music (no flanks) never hides the timer")
        timer.collapsedPreference = .timer
        XCTAssertEqual(timer.state.run, deadline)
    }

    func testInterruptionsReturnToTheSameTimerActivity() {
        let timer = model()
        timer.startTimer()
        let id = timer.activities.primary?.id
        for interruption in [NotchNotification.audio(.init(kind: .volume, deviceName: "Speakers", volume: 0.4, isMuted: false)),
                             NotchNotification(kind: .screenshot, coalescingKey: "screenshot", action: .shelf,
                                               presentationStyle: .compact,
                                               content: .compact(.init(glyph: .symbol("camera"), title: "Shot", trailing: .text("Saved")))),
                             NotchNotification(kind: .reminder5, coalescingKey: "calendar.e", action: .calendar,
                                               presentationStyle: .calendar, content: .calendar(title: "Standup", status: "in 5 min"))] {
            timer.activities.notifications.present(interruption)
            XCTAssertNotEqual(timer.activities.primary?.id, id, "\(interruption.kind) interrupts")
            XCTAssertTrue(timer.activities.liveActivities.contains { $0.id == id }, "The timer stays alive underneath")
            timer.activities.dismiss(key: NotchActivityKey(interruption.coalescingKey))
            XCTAssertEqual(timer.activities.primary?.id, id, "\(interruption.kind) returns to the timer")
        }
        XCTAssertEqual(timer.state.run, .running(endsAt: at(30)))
    }

    func testDownloadAndTimerRankDeterministically() {
        let timer = model()
        timer.startTimer()
        timer.activities.notifications.present(NotchNotification(
            kind: .transferActive, dismissible: false, coalescingKey: "transfer", action: .shelf, presentationStyle: .compact,
            content: .compact(.init(glyph: .symbol("arrow.down.circle.fill"), title: "Downloading", trailing: .progress(0.2, label: "20%"))),
            lifetime: .persistent, minimal: .progress(0.2)))
        XCTAssertEqual(timer.activities.primary?.key.rawValue, PomodoroModel.activityKey, "Equal baselines: the earlier keeps the notch")
        XCTAssertEqual(timer.activities.secondary?.key.rawValue, "transfer")
        timer.collapsedPreference = .music
        XCTAssertEqual(timer.activities.primary?.key.rawValue, "transfer", "The timer yields when set to sit behind Music")
        XCTAssertEqual(timer.state.run, .running(endsAt: at(30)))
    }

    func testPresentationChangesNeverResetTheTimer() {
        let presentation = DynamicIslandPresentationModel(clock: TestAppClock(now: t0, automaticallyAdvances: false))
        defer { presentation.reset() }
        var now = t0
        let timer = PomodoroModel(store: InMemoryPomodoroStore(), notifications: presentation.notificationCoordinator,
                                  clock: TestAppClock(now: t0, automaticallyAdvances: false),
                                  preferences: defaults(), calendar: calendar, now: { now })
        presentation.pomodoroRenderer = timer
        timer.startTimer()
        let state = timer.state
        presentation.present(.expanded, animated: false)
        for page in NotchPage.allCases { presentation.pageModel.selectedPage = page }
        timer.setPageVisible(true)
        timer.setPageVisible(false)
        presentation.present(.collapsed, animated: false)
        now = at(1)
        timer.refresh()
        XCTAssertEqual(timer.state, state)
        presentation.activateCurrentActivity()
        XCTAssertEqual(presentation.pageModel.selectedPage, .pomodoro, "Clicking the timer opens its page")
        XCTAssertEqual(timer.state, state)
    }

    // MARK: Paused presentation

    func testPausedTimerLeavesTheCollapsedNotchAfterTheSharedExpiryInEveryPhase() async {
        for phase in [PomodoroPhase.focus, .shortBreak, .longBreak] {
            var seeded = PomodoroState()
            seeded.phase = phase
            seeded.cyclePosition = phase == .longBreak ? 4 : (phase == .shortBreak ? 1 : 0)
            PomodoroEngine.start(&seeded, configuration: config, at: t0)
            let clock = TestAppClock(now: t0, automaticallyAdvances: false)
            var now = t0
            let timer = model(store: InMemoryPomodoroStore(PomodoroArchive(state: seeded)), clock: clock, now: { now })
            timer.start()
            let id = timer.activities.liveActivities.first { $0.key.rawValue == PomodoroModel.activityKey }?.id
            XCTAssertNotNil(id, "\(phase) running is visible")

            now = at(2)
            timer.pause()
            let paused = timer.state
            XCTAssertFalse(timer.hidesPausedTimer, "\(phase): visible briefly after pausing")
            XCTAssertTrue(timer.activities.liveActivities.contains { $0.id == id })
            await expirePausedPresentation(timer, clock: clock)
            XCTAssertTrue(timer.hidesPausedTimer, "\(phase) hides after the shared paused-content interval")
            XCTAssertFalse(timer.activities.liveActivities.contains { $0.key.rawValue == PomodoroModel.activityKey })
            XCTAssertEqual(timer.state, paused, "Hiding never ends or changes the timer")

            now = at(40)
            timer.resume()
            XCTAssertFalse(timer.hidesPausedTimer)
            XCTAssertEqual(timer.activities.liveActivities.first { $0.key.rawValue == PomodoroModel.activityKey }?.id, id,
                           "\(phase) returns at once with the same identity")
            guard case let .paused(remaining) = paused.run else { return XCTFail() }
            XCTAssertEqual(timer.state.run, .running(endsAt: at(40).addingTimeInterval(remaining)))
            timer.stop()
        }
    }

    func testHiddenPausedTimerLetsPlayingMusicTakeTheNotchAndReturnsOnResume() async {
        let clock = TestAppClock(now: t0, automaticallyAdvances: false)
        var now = t0
        let timer = model(clock: clock, now: { now })
        timer.activities.present(music(visible: true))
        timer.startTimer()
        let id = timer.activities.primary?.id
        XCTAssertEqual(timer.activities.primary?.key.rawValue, PomodoroModel.activityKey)
        now = at(3)
        timer.pause()
        await expirePausedPresentation(timer, clock: clock)
        XCTAssertEqual(timer.activities.primary?.key, .media, "Playing Music becomes the collapsed presentation")
        timer.activities.present(music(visible: false))
        XCTAssertNil(timer.activities.primary?.minimal, "Paused Music too: the notch is idle")
        now = at(9)
        timer.resume()
        XCTAssertEqual(timer.activities.primary?.id, id)
        XCTAssertEqual(timer.state.run, .running(endsAt: at(36)))
    }

    func testPausedTimeNeverCountsAndResumeSetsANewDeadline() {
        var now = t0
        let timer = model(now: { now })
        timer.startTimer()
        now = at(10)
        timer.pause()
        now = at(70)
        timer.refresh()
        XCTAssertEqual(timer.state.run, .paused(remaining: 20 * 60), "Remaining stays fixed while paused")
        XCTAssertEqual(timer.statistics().todayFocus, 10 * 60, "No Focus time accumulates while paused")
        XCTAssertEqual(timer.countdown().remaining(at: at(500)), 20 * 60)
        timer.resume()
        XCTAssertEqual(timer.state.run, .running(endsAt: at(90)), "now + paused remaining")
        now = at(90)
        timer.refresh()
        XCTAssertEqual(timer.records.last?.focusedDuration, 30 * 60)
        XCTAssertEqual(timer.records.last?.segments.map(\.duration), [10 * 60, 20 * 60])
    }

    func testRelaunchWhilePausedStaysHiddenUntilResumed() {
        var seeded = PomodoroState()
        PomodoroEngine.start(&seeded, configuration: config, at: t0)
        PomodoroEngine.pause(&seeded, at: at(5))
        var now = at(500)
        let timer = model(store: InMemoryPomodoroStore(PomodoroArchive(state: seeded)), now: { now })
        timer.start()
        XCTAssertTrue(timer.hidesPausedTimer)
        XCTAssertNil(timer.activities.primary)
        XCTAssertEqual(timer.state, seeded)
        now = at(501)
        timer.resume()
        XCTAssertEqual(timer.activities.primary?.key.rawValue, PomodoroModel.activityKey)
        timer.stop()
    }

    func testBreakGlyphsAreNotTheCaffeineCup() {
        let timer = model()
        timer.startTimer()
        timer.skip()
        timer.startTimer()
        XCTAssertEqual(timer.activities.notifications.active?.content.compactActivity?.glyph, .symbol("leaf.fill"))
        XCTAssertEqual(PomodoroStyle.symbol(.longBreak), "beach.umbrella.fill")
    }

    // MARK: Helpers

    /// Lets the paused-content expiry elapse on the test clock, however its sleep was registered.
    private func expirePausedPresentation(_ timer: PomodoroModel, clock: TestAppClock) async {
        for _ in 0..<20 where !timer.hidesPausedTimer {
            await drainMainActorTasks()
            await clock.advance(by: ActivityPriorityPolicy.pausedPresentationExpiry)
            await drainMainActorTasks()
        }
    }

    private func record(start: Date, minutes: Double, completed: Bool = true) -> FocusSessionRecord {
        let end = start.addingTimeInterval(minutes * 60)
        return FocusSessionRecord(id: UUID(), start: start, end: end, segments: [DateInterval(start: start, end: end)],
                                  completed: completed, cycleIndex: 1)
    }

    private func defaults() -> UserDefaults {
        let name = "notchium.tests.pomodoro.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func model(store: InMemoryPomodoroStore = InMemoryPomodoroStore(), clock: TestAppClock? = nil,
                       now: (() -> Date)? = nil) -> PomodoroModel {
        let activities = ActivityCoordinator(clock: clock ?? TestAppClock(now: t0, automaticallyAdvances: false))
        addTeardownBlock { @MainActor in activities.clearAll() }
        let start = t0
        let timer = PomodoroModel(store: store, notifications: activities.notifications,
                                  clock: clock ?? TestAppClock(now: t0, automaticallyAdvances: false),
                                  preferences: defaults(), calendar: calendar, now: now ?? { start })
        retained.append(activities)
        return timer
    }

    private var retained: [ActivityCoordinator] = []

    private func music(visible: Bool) -> NotchActivity {
        NotchActivity(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, key: .media, kind: .media,
                      title: "Media", subtitle: nil, priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
                      isDismissible: false, destination: .music, duration: nil,
                      payload: .mediaPlayback(isPlaying: visible), minimal: visible ? .artwork : nil)
    }
}

private extension PomodoroModel {
    /// The coordinator behind this model's notification slot.
    var activities: ActivityCoordinator { notificationsForTesting.activities! }
}
