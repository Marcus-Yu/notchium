import AppKit
import NotchiumCore
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumFocusFeature

@MainActor
final class PomodoroCompletionTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    func testEveryCompletionPresentsASmallBannerWithNextPhaseControls() async {
        for phase in [PomodoroPhase.focus, .shortBreak, .longBreak] {
            let fixture = completedPhase(phase)
            fixture.timer.refresh()
            let notification = fixture.presentation.presentedNotification
            XCTAssertEqual(notification?.presentationStyle, .pomodoroCompletion)
            XCTAssertEqual(notification?.lifetime, .transient)
            XCTAssertEqual(notification?.duration, .seconds(20))
            XCTAssertEqual(notification?.activity.presentationStyle, .downwardBanner)
            XCTAssertEqual(fixture.presentation.visualState, .collapsed, "Completion does not open the full page")
            XCTAssertEqual(fixture.timer.state.run, .ready)
            XCTAssertEqual(fixture.timer.state.controls, phase == .focus
                ? [.addFiveMinutes, .startBreak, .skip] : [.addFiveMinutes, .startFocus])
            let title = phase == .focus ? "Focus Complete" : (phase == .longBreak ? "Cycle Complete" : "Break Over")
            XCTAssertEqual(notification?.content, .pomodoroCompletion(title: title))
            await fixture.clock.waitForPendingSleeps()
            let deadline = fixture.presentation.notificationCoordinator.expiresAt
            let presentedAt = await fixture.clock.now()
            XCTAssertEqual(deadline, presentedAt.addingTimeInterval(20))
            fixture.presentation.notificationCoordinator.setHovered(true)
            fixture.timer.perform(.addFiveMinutes)
            await fixture.clock.advance(by: .milliseconds(19_999))
            await drain()
            XCTAssertEqual(fixture.presentation.presentedNotification?.id, notification?.id,
                           "The banner remains available for the full 20 seconds")
            XCTAssertEqual(fixture.presentation.notificationCoordinator.expiresAt, deadline,
                           "Hover and + 5 mins do not extend the notification's lifetime")
            await fixture.clock.advance(by: .milliseconds(1))
            await drain()
            XCTAssertNil(fixture.presentation.presentedNotification)
            XCTAssertEqual(fixture.timer.state.run, .ready, "Expiry does not start the next phase")
        }
    }

    func testFocusAtEndOfCycleOffersLongBreakControls() {
        let fixture = completedPhase(.focus, configuration: .init(sessionsPerCycle: 1))
        fixture.timer.refresh()
        XCTAssertEqual(fixture.timer.state.phase, .longBreak)
        XCTAssertEqual(fixture.timer.state.controls, [.addFiveMinutes, .startBreak, .skip])
    }

    func testExtensionKeepsBannerAndStartingOrSkippingConsumesIt() {
        for control in [PomodoroControl.startBreak, .skip] {
            let fixture = completedPhase(.focus)
            fixture.timer.refresh()
            let id = fixture.presentation.presentedNotification?.id
            fixture.timer.perform(.addFiveMinutes)
            XCTAssertEqual(fixture.presentation.presentedNotification?.id, id)
            XCTAssertEqual(fixture.timer.countdown().remaining(at: base), 600)
            fixture.timer.perform(control)
            XCTAssertFalse(fixture.presentation.activityCoordinator.liveActivities.contains { $0.key.rawValue == PomodoroModel.resultKey })
            if control == .startBreak {
                XCTAssertEqual(fixture.timer.state.phase, .shortBreak)
                XCTAssertTrue(fixture.timer.countdown().isRunning)
            } else {
                XCTAssertEqual(fixture.timer.state.phase, .focus)
                XCTAssertTrue(fixture.timer.countdown().isRunning)
                XCTAssertEqual(fixture.timer.state.run,
                               .running(endsAt: base.addingTimeInterval(1800 + 1800)))
            }
        }
        let fixture = completedPhase(.shortBreak)
        fixture.timer.refresh()
        fixture.timer.perform(.startFocus)
        XCTAssertEqual(fixture.presentation.notificationCoordinator.active?.kind, .focusTimer)
        XCTAssertEqual(fixture.timer.state.phase, .focus)
        XCTAssertTrue(fixture.timer.countdown().isRunning)
    }

    func testDismissalAndEscapeLeaveTheNextPhaseReadyAndDoNotReannounce() {
        for escape in [true, false] {
            let fixture = completedPhase(.focus)
            fixture.timer.completionSound = .ping
            fixture.timer.refresh()
            let state = fixture.timer.state
            if escape { fixture.presentation.handleEscape() } else { fixture.timer.dismissCompletion() }
            XCTAssertNil(fixture.presentation.presentedNotification)
            XCTAssertEqual(fixture.timer.state, state)
            fixture.timer.refresh()
            fixture.timer.configuration.shortBreakMinutes = 10
            XCTAssertNil(fixture.presentation.presentedNotification)
            XCTAssertEqual(fixture.sounds.played, [.ping], "Refresh and presentation changes do not replay the alert")
        }
    }

    func testOtherNotificationsInterruptAndRestoreCompletionWithoutReplayingSound() async {
        let fixture = completedPhase(.focus)
        fixture.timer.completionSound = .glass
        fixture.timer.refresh()
        let id = fixture.presentation.presentedNotification?.id
        fixture.presentation.notificationCoordinator.present(.criticalBattery(level: 0.02))
        XCTAssertEqual(fixture.presentation.presentedNotification?.kind, .criticalBattery)
        await fixture.clock.waitForPendingSleeps()
        await fixture.clock.advance(by: .seconds(6))
        await drain()
        XCTAssertEqual(fixture.presentation.presentedNotification?.id, id)
        XCTAssertEqual(fixture.sounds.played, [.glass])
    }

    func testCompletionDoesNotReplaceAnAlreadyOpenPage() {
        let fixture = completedPhase(.focus)
        fixture.presentation.setExpanded(true)
        fixture.presentation.pageModel.selectedPage = .calendar
        fixture.timer.refresh()
        XCTAssertEqual(fixture.presentation.visualState, .expanded)
        XCTAssertEqual(fixture.presentation.pageModel.selectedPage, .calendar)
        XCTAssertNil(fixture.presentation.presentedNotification)
        fixture.presentation.collapse()
        XCTAssertEqual(fixture.presentation.presentedNotification?.presentationStyle, .pomodoroCompletion)
    }

    func testCompletionExpiresWhileFullNotchIsOpenAndDoesNotReturnOnCollapse() async {
        let fixture = completedPhase(.focus)
        fixture.presentation.setExpanded(true)
        fixture.timer.refresh()
        await fixture.clock.waitForPendingSleeps()
        await fixture.clock.advance(by: .seconds(20))
        await drain()
        fixture.presentation.collapse()
        XCTAssertNil(fixture.presentation.presentedNotification)
        XCTAssertEqual(fixture.timer.state.run, .ready)
    }

    func testBannerBodyHoverAndClicksKeepTheCompactSurfaceWhileHeaderCanExpand() async {
        let fixture = completedPhase(.focus)
        fixture.timer.refresh()
        let controller = NotchiumPanelController(model: fixture.presentation)
        defer { controller.hide() }
        let placement = NotchShellPlacement(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch)
        let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)
        controller.reconcile(placement: placement, layout: layout, renderConfiguration: .automatic, animated: false)
        let frame = NotchNotificationGeometry.frame(for: .pomodoroCompletion, layout: layout)
        XCTAssertEqual(frame.width, NotchReminderGeometry.width(for: layout))
        XCTAssertLessThan(frame.height, layout.expandedSize.height)
        let point = CGPoint(x: frame.midX, y: layout.collapsedVisibleFrame.minY - 50)
        controller.handleMouseMoved(at: point)
        await drain()
        await fixture.clock.advance(by: .seconds(1))
        await drain()
        XCTAssertEqual(fixture.presentation.visualState, .collapsed)
        controller.handleClick(at: point)
        XCTAssertEqual(fixture.presentation.visualState, .collapsed, "Banner buttons own the click")
        controller.handleClick(at: CGPoint(x: layout.collapsedHoverFrame.midX, y: layout.collapsedHoverFrame.midY))
        XCTAssertEqual(fixture.presentation.visualState, .expanded)
    }

    func testClickingBannerTitleOpensFocusTimer() {
        let fixture = completedPhase(.focus)
        fixture.timer.refresh()
        fixture.presentation.activateCurrentActivity()
        XCTAssertEqual(fixture.presentation.visualState, .expanded)
        XCTAssertEqual(fixture.presentation.pageModel.selectedPage, .pomodoro)
        XCTAssertEqual(fixture.timer.state.run, .ready)
    }

    func testStaleCompletionsStaySilentAndDoNotExpand() {
        let fixture = completedPhase(.focus, lateness: 121)
        fixture.timer.completionSound = .hero
        fixture.timer.refresh()
        XCTAssertEqual(fixture.timer.records.count, 1)
        XCTAssertEqual(fixture.timer.state.phase, .shortBreak)
        XCTAssertNil(fixture.presentation.presentedNotification)
        XCTAssertTrue(fixture.sounds.played.isEmpty)
    }

    func testSoundPreviewAndSelectionPersistenceDoNotChangeTimer() {
        let fixture = completedPhase(.focus)
        let state = fixture.timer.state
        fixture.timer.completionSound = .morse
        fixture.timer.previewCompletionSound()
        XCTAssertEqual(fixture.timer.state, state)
        XCTAssertEqual(fixture.sounds.played, [.morse])
        let restored = makeModel(state: state, date: base, preferences: fixture.preferences)
        XCTAssertEqual(restored.timer.completionSound, .morse)
        fixture.timer.completionSound = .none
        fixture.timer.previewCompletionSound()
        fixture.timer.refresh()
        XCTAssertEqual(fixture.sounds.played, [.morse])
        XCTAssertEqual(makeModel(state: state, date: base, preferences: fixture.preferences).timer.completionSound, .none)
    }

    func testLegacySoundPreferenceMigratesAndExplicitSelectionWins() {
        for enabled in [true, false] {
            let preferences = defaults()
            preferences.set(enabled, forKey: "notchium.pomodoro.sound.v1")
            let fixture = makeModel(state: PomodoroState(), date: base, preferences: preferences)
            XCTAssertEqual(fixture.timer.completionSound, enabled ? .glass : .none)
            fixture.timer.completionSound = .ping
            XCTAssertEqual(makeModel(state: PomodoroState(), date: base, preferences: preferences).timer.completionSound, .ping)
        }
    }

    func testEveryOfferedSoundIsAvailableOnMacOS() {
        for sound in PomodoroSound.allCases where sound != .none {
            XCTAssertNotNil(sound.systemName.flatMap { NSSound(named: $0) }, sound.title)
        }
    }

    private struct Fixture {
        let timer: PomodoroModel
        let presentation: DynamicIslandPresentationModel
        let clock: TestAppClock
        let sounds: RecordingPomodoroSoundPlayer
        let preferences: UserDefaults
    }

    private func completedPhase(_ phase: PomodoroPhase, configuration: PomodoroConfiguration = .standard,
                                lateness: TimeInterval = 0) -> Fixture {
        var state = PomodoroState()
        state.phase = phase
        state.cyclePosition = phase == .longBreak ? configuration.sessionsPerCycle : 0
        PomodoroEngine.start(&state, configuration: configuration, at: base)
        let fixture = makeModel(state: state, date: base.addingTimeInterval(configuration.duration(of: phase) + lateness))
        fixture.timer.configuration = configuration
        return fixture
    }

    private func makeModel(state: PomodoroState, date: Date, preferences: UserDefaults? = nil) -> Fixture {
        let clock = TestAppClock(now: date, automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let sounds = RecordingPomodoroSoundPlayer()
        let preferences = preferences ?? defaults()
        let timer = PomodoroModel(store: InMemoryPomodoroStore(PomodoroArchive(state: state)),
            notifications: presentation.notificationCoordinator, clock: clock, preferences: preferences,
            now: { date }, soundPlayer: sounds)
        presentation.pomodoroRenderer = timer
        addTeardownBlock { @MainActor in timer.stop(); presentation.reset() }
        return Fixture(timer: timer, presentation: presentation, clock: clock, sounds: sounds, preferences: preferences)
    }

    private func defaults() -> UserDefaults {
        let name = "notchium.tests.pomodoro.completion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func drain() async { for _ in 0..<200 { await Task.yield() } }
}

@MainActor private final class RecordingPomodoroSoundPlayer: PomodoroSoundPlaying {
    var played: [PomodoroSound] = []
    func play(_ sound: PomodoroSound) { played.append(sound) }
    func stop() {}
}
