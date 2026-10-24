import Combine
import NotchiumCore
@testable import NotchiumDynamicIsland
import SwiftUI
import XCTest

@MainActor
final class CalendarCollapsedRowTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 10_000)

    func testCalendarKeepsTimerAndEmbeddedMusicWithoutDuplicatingChips() {
        let model = presentation()
        defer { model.reset() }
        let timer = timer()
        model.activityCoordinator.present(music())
        model.notificationCoordinator.present(timer)
        let row = model.collapsedRowNotification

        model.notificationCoordinator.present(calendar())

        XCTAssertTrue(model.retainsCalendarRow)
        XCTAssertEqual(model.presentedNotification?.presentationStyle, .calendar)
        XCTAssertEqual(model.collapsedRowNotification, row)
        XCTAssertEqual(model.activityCoordinator.persistentNotification, row)
        XCTAssertTrue(model.mediaVisiblyPlaying)
        XCTAssertEqual(model.activityCoordinator.presentationMode, .combined)
        XCTAssertTrue(model.presentedIndicators.isEmpty, "Music already lives inside the timer row")
    }

    func testMusicPreferenceKeepsMusicAndSameTimerCompanion() {
        let model = presentation()
        defer { model.reset() }
        model.activityCoordinator.present(music())
        model.notificationCoordinator.present(timer(prefersMusic: true))
        let companion = model.presentedIndicators
        let width = model.collapsedRowWidth(in: layout())

        model.notificationCoordinator.present(calendar())

        XCTAssertNil(model.collapsedRowNotification)
        XCTAssertEqual(model.presentedIndicators, companion)
        XCTAssertEqual(model.presentedIndicators.map(\.kind), [.pomodoro])
        XCTAssertEqual(model.collapsedRowWidth(in: layout()), width)
        XCTAssertEqual(model.activityCoordinator.presentationMode, .combined)
    }

    func testTimerOnlyKeepsFullCountdownAndOpensTimerWithoutDismissingCalendar() {
        let model = presentation()
        defer { model.reset() }
        let timer = timer()
        let calendar = calendar()
        model.notificationCoordinator.present(timer)
        model.notificationCoordinator.present(calendar)

        XCTAssertEqual(model.collapsedRowNotification?.content, timer.content)
        XCTAssertEqual(model.activityCoordinator.presentationMode, .downwardBanner)
        XCTAssertTrue(model.retainsCalendarRow, "Row retention must not require Music")
        model.activateCollapsedRow()
        XCTAssertEqual(model.pageModel.selectedPage, .pomodoro)
        XCTAssertTrue(model.activityCoordinator.contains(id: calendar.id))
    }

    func testPausedMusicStopsEmbeddingWithoutLosingTimerOrCalendar() {
        let model = presentation()
        defer { model.reset() }
        model.activityCoordinator.present(music())
        model.notificationCoordinator.present(timer())
        model.notificationCoordinator.present(calendar())
        let row = model.collapsedRowNotification

        model.activityCoordinator.present(music(playing: false))

        XCTAssertFalse(model.mediaVisiblyPlaying)
        XCTAssertEqual(model.collapsedRowNotification, row)
        XCTAssertTrue(model.presentedIndicators.isEmpty)
        XCTAssertEqual(model.presentedNotification?.presentationStyle, .calendar)
    }

    func testTransferAndItsMusicCompanionKeepTheirNormalGeometryAndLiveContent() {
        let model = presentation()
        defer { model.reset() }
        model.activityCoordinator.present(music())
        model.notificationCoordinator.present(transfer(progress: 0.2))
        let companion = model.presentedIndicators
        let rowWidth = model.collapsedRowWidth(in: layout())
        let frame = NotchSecondaryGeometry.frame(layout: layout(), beside: model.collapsedRowNotification)
        model.notificationCoordinator.present(calendar())

        XCTAssertEqual(model.collapsedRowNotification?.kind, .transferActive)
        XCTAssertEqual(model.presentedIndicators, companion)
        XCTAssertEqual(model.collapsedRowWidth(in: layout()), rowWidth)
        XCTAssertEqual(NotchSecondaryGeometry.frame(layout: layout(), beside: model.collapsedRowNotification), frame)
        let id = model.collapsedRowNotification?.id
        model.notificationCoordinator.present(transfer(progress: 0.7))
        XCTAssertEqual(model.collapsedRowNotification?.id, id)
        XCTAssertEqual(model.collapsedRowNotification?.minimal, .progress(0.7))
    }

    func testUnderlyingContentChangePublishesEvenWhenActivityAndCalendarStayUnchanged() {
        let model = presentation()
        defer { model.reset() }
        model.notificationCoordinator.present(transfer(progress: 0.2, label: "First"))
        model.notificationCoordinator.present(calendar())
        let baseline = model.activityCoordinator.persistentActivity
        var resolutions = 0
        let observation = model.activityCoordinator.presentationDidResolve.sink { resolutions += 1 }
        defer { observation.cancel() }

        model.notificationCoordinator.present(transfer(progress: 0.2, label: "Updated"))

        XCTAssertTrue(baseline.map { model.activityCoordinator.persistentActivity?.hasSamePresentation(as: $0) == true } == true)
        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(model.collapsedRowNotification?.content.compactActivity?.trailing,
                       .progress(0.2, label: "Updated"))
    }

    func testProviderRemovalOfTimerAndMusicCannotLeaveCachedDetailsInCalendarRow() async {
        let clock = TestAppClock(now: date, automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(clock: clock)
        defer { model.reset() }
        let timer = timer()
        model.activityCoordinator.present(music())
        model.notificationCoordinator.present(timer)
        model.notificationCoordinator.present(calendar())
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(250))
        model.activityCoordinator.dismiss(key: NotchActivityKey(timer.coalescingKey))

        XCTAssertNil(model.collapsedRowNotification)
        XCTAssertTrue(model.presentedIndicators.isEmpty)
        model.activityCoordinator.dismiss(key: .media)
        XCTAssertNil(model.activityCoordinator.persistentNotification)
        XCTAssertFalse(model.mediaVisiblyPlaying)
        XCTAssertTrue(model.presentedIndicators.isEmpty)
        XCTAssertEqual(model.presentedNotification?.presentationStyle, .calendar)
    }

    func testCalendarExpiryRestoresSameBaselineAndTimerDeadline() async {
        let clock = TestAppClock(now: date, automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(clock: clock)
        defer { model.reset() }
        let timer = timer()
        model.notificationCoordinator.present(timer)
        model.notificationCoordinator.present(calendar())
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(5))
        await waitUntil { model.presentedNotification?.kind == .focusTimer }

        XCTAssertEqual(model.collapsedRowNotification?.id, timer.id)
        XCTAssertEqual(model.collapsedRowNotification?.content, timer.content)
        XCTAssertFalse(model.retainsCalendarRow)
    }

    private func presentation() -> DynamicIslandPresentationModel {
        let model = DynamicIslandPresentationModel(clock: TestAppClock(now: date, automaticallyAdvances: false))
        model.mediaRenderer = CalendarRowTestMedia()
        return model
    }

    private func layout() -> NotchPanelLayout {
        NotchGeometryResolver.layout(for: .init(display: NotchShellDebugModel.builtInFixture,
                                                 mode: .physicalNotch), state: .collapsed)
    }

    private func music(playing: Bool = true) -> NotchActivity {
        .init(id: UUID(), key: .media, kind: .media, title: "Music", subtitle: nil,
              priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
              destination: .music, duration: nil, payload: .mediaPlayback(isPlaying: playing),
              minimal: playing ? .artwork : nil)
    }

    private func timer(prefersMusic: Bool = false) -> NotchNotification {
        let countdown = NotchCountdown.running(total: 1500, endsAt: date.addingTimeInterval(1500))
        return .init(kind: prefersMusic ? .focusTimerBesideMusic : .focusTimer,
                     coalescingKey: "timer", action: .pomodoro, presentationStyle: .compact,
                     content: .compact(.init(glyph: .symbol("timer"), title: "Focus", trailing: .countdown(countdown),
                                             blendsWithMedia: true)),
                     lifetime: .persistent, minimal: .countdown(countdown))
    }

    private func transfer(progress: Double, label: String = "First") -> NotchNotification {
        .init(kind: .transferActive, dismissible: false, coalescingKey: "transfer", action: .shelf,
              presentationStyle: .compact,
              content: .compact(.init(glyph: .symbol("arrow.down.circle"), title: "Download",
                                      trailing: .progress(progress, label: label))),
              lifetime: .persistent, minimal: .progress(progress))
    }

    private func calendar() -> NotchNotification {
        .init(kind: .reminder5, duration: .seconds(5), coalescingKey: "calendar.test", action: .calendar,
              presentationStyle: .calendar, content: .calendar(title: "Meeting", status: "Now"))
    }
}

@MainActor private final class CalendarRowTestMedia: NotchMediaRendering {
    let collapsedMediaVisible = true
    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView { AnyView(EmptyView()) }
    func expandedMedia() -> AnyView { AnyView(EmptyView()) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(EmptyView()) }
}
