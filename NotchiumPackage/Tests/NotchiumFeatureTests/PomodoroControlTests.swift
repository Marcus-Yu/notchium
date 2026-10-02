import Foundation
import NotchiumCore
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumFocusFeature

@MainActor
final class PomodoroControlTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testControlsMatchEachPhaseAndRunState() {
        for phase in [PomodoroPhase.focus, .shortBreak, .longBreak] {
            var state = PomodoroState()
            state.phase = phase
            XCTAssertEqual(state.controls.map(\.title), phase.isBreak
                ? ["+ 5 mins", "Start Break", "Skip"] : ["+ 5 mins", "Start Focus"])
            state.run = .running(endsAt: now.addingTimeInterval(300))
            XCTAssertEqual(state.controls.map(\.title), phase.isBreak ? ["Pause", "Skip Break"] : ["Pause"])
            state.run = .paused(remaining: 240)
            XCTAssertEqual(state.controls.map(\.title), phase.isBreak
                ? ["Resume", "Start Focus"] : ["Resume", "Take Break", "End Focus"])
        }
    }

    func testFiveMinuteExtensionsPersistAndApplyOnlyToTheUpcomingPhase() throws {
        for phase in [PomodoroPhase.focus, .shortBreak, .longBreak] {
            let configuration = PomodoroConfiguration.standard
            var state = PomodoroState()
            state.phase = phase
            state.cyclePosition = phase == .longBreak ? 4 : 1
            PomodoroEngine.addFiveMinutes(&state, configuration: configuration)
            PomodoroEngine.addFiveMinutes(&state, configuration: configuration)
            XCTAssertEqual(state.run, .ready)
            XCTAssertNil(state.session)
            let duration = configuration.duration(of: phase) + 600
            XCTAssertEqual(PomodoroEngine.remaining(state, configuration: configuration, at: now), duration)

            let data = try JSONEncoder().encode(PomodoroArchive(state: state))
            state = try JSONDecoder().decode(PomodoroArchive.self, from: data).state
            PomodoroEngine.start(&state, configuration: configuration, at: now)
            XCTAssertEqual(state.run, .running(endsAt: now.addingTimeInterval(duration)))
            PomodoroEngine.addFiveMinutes(&state, configuration: configuration)
            XCTAssertEqual(state.phaseDuration, duration, "Running phases cannot be extended")
            PomodoroEngine.pause(&state, at: now.addingTimeInterval(60))
            PomodoroEngine.addFiveMinutes(&state, configuration: configuration)
            XCTAssertEqual(state.phaseDuration, duration, "Paused started phases cannot be extended")
            PomodoroEngine.resume(&state, at: now.addingTimeInterval(120))
            _ = PomodoroEngine.advance(&state, configuration: configuration, to: now.addingTimeInterval(duration + 60))
            XCTAssertEqual(state.phaseDuration, 0)
            XCTAssertEqual(PomodoroEngine.remaining(state, configuration: configuration, at: now),
                           configuration.duration(of: state.phase), "The extension does not carry into the next phase")
        }
    }

    func testSkipUnstartedBreakReadiesFocusAndResetsOnlyALongBreakCycle() {
        for phase in [PomodoroPhase.shortBreak, .longBreak] {
            var state = PomodoroState()
            state.phase = phase
            state.cyclePosition = phase == .longBreak ? 4 : 1
            PomodoroEngine.addFiveMinutes(&state, configuration: .standard)
            XCTAssertTrue(PomodoroEngine.skip(&state, configuration: .standard, at: now).isEmpty)
            XCTAssertEqual(state.phase, .focus)
            XCTAssertEqual(state.run, .ready)
            XCTAssertEqual(state.phaseDuration, 0)
            XCTAssertEqual(state.cyclePosition, phase == .longBreak ? 0 : 1)
        }
    }

    func testPausedFocusCanTakeBreakWithoutRecordingPausedTime() {
        var date = now
        let timer = makeModel(now: { date })
        timer.perform(.startFocus)
        date += 120
        timer.perform(.pause)
        date += 600
        timer.perform(.takeBreak)
        XCTAssertEqual(timer.state.phase, .shortBreak)
        XCTAssertEqual(timer.state.run, .ready)
        XCTAssertEqual(timer.records.count, 1)
        XCTAssertEqual(timer.records.first?.focusedDuration, 120)
        XCTAssertEqual(timer.records.first?.completed, false)
        timer.perform(.skip)
        XCTAssertEqual(timer.state.phase, .focus)
        XCTAssertEqual(timer.state.cyclePosition, 1)
    }

    func testPausedBreakStartFocusStartsANewFocusImmediately() {
        for phase in [PomodoroPhase.shortBreak, .longBreak] {
            var state = PomodoroState()
            state.phase = phase
            state.cyclePosition = phase == .longBreak ? 4 : 1
            state.phaseDuration = 300
            state.run = .paused(remaining: 240)
            let timer = makeModel(store: InMemoryPomodoroStore(PomodoroArchive(state: state)), now: { self.now })
            timer.perform(.startFocus)
            XCTAssertEqual(timer.state.phase, .focus)
            XCTAssertEqual(timer.state.run, .running(endsAt: now.addingTimeInterval(1800)))
            XCTAssertEqual(timer.state.session?.segmentStart, now)
            XCTAssertEqual(timer.state.cyclePosition, phase == .longBreak ? 0 : 1)
            XCTAssertTrue(timer.records.isEmpty)
        }
    }

    func testPausedFocusResumePreservesSessionAndEndFocusResetsTimer() {
        var date = now
        let timer = makeModel(now: { date })
        timer.perform(.addFiveMinutes)
        timer.perform(.startFocus)
        let id = timer.state.session?.id
        date += 120
        timer.perform(.pause)
        date += 600
        timer.perform(.resume)
        XCTAssertEqual(timer.state.session?.id, id)
        XCTAssertEqual(timer.state.run, .running(endsAt: date.addingTimeInterval(1980)))
        date += 60
        timer.perform(.pause)
        timer.perform(.endFocus)
        XCTAssertEqual(timer.state, PomodoroState())
        XCTAssertEqual(timer.records.first?.focusedDuration, 180)
        XCTAssertEqual(timer.records.first?.completed, false)
    }

    func testModelPersistsUpcomingExtensionAndCadenceAcrossRelaunch() {
        let preferences = defaults()
        let store = InMemoryPomodoroStore()
        let timer = makeModel(store: store, preferences: preferences, now: { self.now })
        timer.configuration.sessionsPerCycle = 2
        timer.perform(.addFiveMinutes)
        let restored = makeModel(store: store, preferences: preferences, now: { self.now })
        XCTAssertEqual(restored.configuration.sessionsPerCycle, 2)
        XCTAssertEqual(restored.configuration.focusMinutes, 30)
        XCTAssertEqual(restored.countdown().remaining(at: now), 2100)
        restored.perform(.startFocus)
        XCTAssertEqual(restored.state.run, .running(endsAt: now.addingTimeInterval(2100)))
        restored.configuration = .standard
        XCTAssertEqual(restored.configuration.sessionsPerCycle, 4)
        XCTAssertEqual(restored.state.run, .running(endsAt: now.addingTimeInterval(2100)))
    }

    func testLongBreakFollowsTheChosenCadenceForRepeatedCycles() {
        for cadence in [1, 2, 6, 8] {
            let configuration = PomodoroConfiguration(sessionsPerCycle: cadence)
            var state = PomodoroState()
            var date = now
            for _ in 0..<2 {
                for index in 1...cadence {
                    PomodoroEngine.start(&state, configuration: configuration, at: date)
                    date += configuration.duration(of: .focus)
                    _ = PomodoroEngine.advance(&state, configuration: configuration, to: date)
                    XCTAssertEqual(state.phase, index == cadence ? .longBreak : .shortBreak)
                    XCTAssertEqual(state.focusNumber(of: configuration), index)
                    _ = PomodoroEngine.skip(&state, configuration: configuration, at: date)
                }
                XCTAssertEqual(state.cyclePosition, 0)
            }
        }
    }

    private func defaults() -> UserDefaults {
        let name = "notchium.tests.pomodoro.controls.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        addTeardownBlock { preferences.removePersistentDomain(forName: name) }
        return preferences
    }

    private func makeModel(store: InMemoryPomodoroStore = InMemoryPomodoroStore(), preferences: UserDefaults? = nil,
                           now: @escaping () -> Date) -> PomodoroModel {
        let clock = TestAppClock(now: self.now, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let timer = PomodoroModel(store: store, notifications: activities.notifications, clock: clock,
                                  preferences: preferences ?? defaults(), now: now)
        addTeardownBlock { @MainActor in timer.stop(); activities.clearAll() }
        return timer
    }
}
