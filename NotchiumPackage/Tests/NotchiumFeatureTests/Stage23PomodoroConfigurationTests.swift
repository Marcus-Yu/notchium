import Foundation
import NotchiumCore
import Testing
@testable import NotchiumDynamicIsland
@testable import NotchiumFocusFeature

@MainActor
struct Stage23PomodoroConfigurationTests {
    @Test(arguments: [Int.min, -1, 0, Int.max])
    func restoredConfigurationKeepsTimerAndCycleWithinSupportedRanges(_ value: Int) throws {
        let restored = PomodoroConfiguration(focusMinutes: value, shortBreakMinutes: value,
                                              longBreakMinutes: value, sessionsPerCycle: value)
        let timer = try restore(restored)
        defer { timer.stop() }

        try #require((5...120).contains(timer.configuration.focusMinutes))
        try #require((1...30).contains(timer.configuration.shortBreakMinutes))
        try #require((5...60).contains(timer.configuration.longBreakMinutes))
        try #require((1...8).contains(timer.configuration.sessionsPerCycle))
        // The first consumer must produce a finite, usable countdown and a valid dot count.
        #expect(timer.countdown().total.isFinite)
        #expect(timer.focusNumber == 1)
    }

    @Test
    func supportedRestoredConfigurationAndActiveDeadlineArePreserved() throws {
        let configuration = PomodoroConfiguration(focusMinutes: 45, shortBreakMinutes: 8,
                                                  longBreakMinutes: 25, sessionsPerCycle: 6)
        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        var state = PomodoroState()
        state.phaseDuration = 13 * 60
        state.run = .running(endsAt: deadline)
        let timer = try restore(configuration, state: state)
        defer { timer.stop() }

        #expect(timer.configuration == configuration)
        #expect(timer.state.run == .running(endsAt: deadline))
        #expect(timer.state.phaseDuration == 13 * 60)
    }

    @Test
    func explicitOneMinuteEngineFixtureRemainsUsable() {
        let configuration = PomodoroConfiguration(focusMinutes: 1)
        var state = PomodoroState()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        PomodoroEngine.start(&state, configuration: configuration, at: start)
        #expect(state.run == .running(endsAt: start.addingTimeInterval(60)))
    }

    @Test
    func explicitExtremeMinutesDoNotOverflowBeforeTimeIntervalConversion() {
        let configuration = PomodoroConfiguration(focusMinutes: Int.max)
        let duration = configuration.duration(of: .focus)
        #expect(duration.isFinite)
        #expect(duration > 0)
    }

    private func restore(_ configuration: PomodoroConfiguration,
                         state: PomodoroState = PomodoroState()) throws -> PomodoroModel {
        let name = "notchium.stage23.pomodoro.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(try JSONEncoder().encode(configuration), forKey: "notchium.pomodoro.configuration.v1")
        let clock = TestAppClock(now: .distantPast, automaticallyAdvances: false)
        return PomodoroModel(store: InMemoryPomodoroStore(PomodoroArchive(state: state)),
                             notifications: ActivityCoordinator(clock: clock).notifications,
                             clock: clock, preferences: preferences)
    }
}
