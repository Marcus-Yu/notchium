import Combine
import Foundation
import NotchiumCore
import NotchiumServices
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature

/// Stage 12: one arbitration system for every activity — primary/secondary roles,
/// coalescing by stable key, centralized absolute lifetimes, and restoration.
@MainActor
final class Stage12ActivityTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let musicID = UUID()

    private func clock() -> TestAppClock { TestAppClock(now: base, automaticallyAdvances: false) }
    private func drain() async { for _ in 0..<200 { await Task.yield() } }
    /// A reschedule cancels the previous sleeper asynchronously; settle before waiting.
    private func settle(_ clock: TestAppClock) async {
        await drain()
        await clock.waitForPendingSleeps()
    }

    private func music(visible: Bool = true, playing: Bool = true) -> NotchActivity {
        NotchActivity(id: musicID, key: .media, kind: .media, title: "Media", subtitle: nil,
                      priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
                      isDismissible: false, destination: .music, duration: nil,
                      payload: .mediaPlayback(isPlaying: playing), minimal: visible ? .artwork : nil)
    }
    private func volume(_ level: Double) -> NotchNotification {
        .audio(.init(kind: .volume, deviceName: "Speakers", volume: level, isMuted: false))
    }
    private func airPods(_ name: String = "AirPods Pro") -> NotchNotification {
        .audio(.init(kind: .outputChanged, deviceName: name, volume: 0.5, isMuted: false,
                     deviceStyle: .classify(name: name, transport: .bluetooth)))
    }
    private func reminder(_ kind: NotchNotification.Kind = .reminder5, event: String = "event") -> NotchNotification {
        .init(kind: kind, coalescingKey: "calendar.\(event)", action: .calendar,
              presentationStyle: .calendar, content: .calendar(title: "Planning", status: "5 min"))
    }

    // MARK: Music + transient interruptions

    func testMusicVolumeInterruptionCoalescesExpiresAndRestoresSameMusic() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        activities.present(music())
        var musicChanges = 0
        let observation = activities.$persistentActivity.dropFirst().sink { _ in musicChanges += 1 }
        defer { observation.cancel(); activities.clearAll() }

        XCTAssertTrue(activities.notifications.present(volume(0.4)))
        let volumeID = activities.primary?.id
        XCTAssertEqual(activities.primary?.key, NotchActivityKey("audio.level"))
        XCTAssertEqual(activities.presentationMode, .combined)
        await settle(clock)

        // Holding Volume Up: one activity whose value and lifetime update in place.
        for (index, level) in [0.45, 0.5, 0.55, 0.6].enumerated() {
            await clock.advance(by: .milliseconds(500))
            XCTAssertTrue(activities.notifications.present(volume(level)), "update \(index)")
            XCTAssertEqual(activities.primary?.id, volumeID)
        }
        XCTAssertEqual(activities.liveActivities.count, 2)
        XCTAssertEqual(activities.queueCount, 0)
        XCTAssertNil(activities.secondary, "A replaceable volume HUD never spawns a secondary chip")
        await settle(clock)
        XCTAssertEqual(activities.notifications.expiresAt, base.addingTimeInterval(2 + 1.75))

        await clock.advance(by: .milliseconds(1750))
        await waitUntil { activities.primary?.id == self.musicID }
        XCTAssertEqual(activities.primary?.id, musicID)
        XCTAssertNil(activities.notifications.active)
        XCTAssertEqual(activities.presentationMode, .mediaSides)
        XCTAssertEqual(musicChanges, 0, "Music is never recreated by an interruption")
        let sleepers = await clock.pendingSleepCount()
        XCTAssertEqual(sleepers, 0)
    }

    func testMusicAirPodsConnectionShowsMusicAsSecondaryThenMusicReturns() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        activities.present(music())
        defer { activities.clearAll() }

        XCTAssertTrue(activities.notifications.present(airPods()))
        XCTAssertEqual(activities.primary?.kind, .audioDevice)
        XCTAssertEqual(activities.secondary?.id, musicID)
        // A repeated identical device event is not a new card and does not extend the lifetime.
        await settle(clock)
        let deadline = activities.notifications.expiresAt
        await clock.advance(by: .seconds(1))
        activities.notifications.present(airPods())
        XCTAssertEqual(activities.liveActivities.count, 2)
        XCTAssertEqual(activities.notifications.expiresAt, deadline)

        await clock.advance(by: .milliseconds(1500))
        await waitUntil { activities.primary?.id == self.musicID }
        XCTAssertEqual(activities.primary?.id, musicID)
        XCTAssertNil(activities.secondary)
    }

    func testMusicCalendarAlertKeepsMusicAliveAndRestoresIt() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        activities.present(music())
        defer { activities.clearAll() }

        XCTAssertTrue(activities.notifications.present(reminder()))
        XCTAssertEqual(activities.activeTransient?.kind, .calendar)
        XCTAssertEqual(activities.persistentActivity?.id, musicID)
        XCTAssertEqual(activities.presentationMode, .combined, "Music flanks stay in the top row")
        XCTAssertNil(activities.secondary, "A downward banner already keeps Music visible")

        await settle(clock)
        await clock.advance(by: .seconds(5))
        await waitUntil { activities.activeTransient == nil }
        XCTAssertEqual(activities.primary?.id, musicID)
    }

    // MARK: Priority

    func testHigherPriorityInterruptsLowerAndLowerCannotReplaceHigher() {
        let activities = ActivityCoordinator(clock: clock())
        defer { activities.clearAll() }
        XCTAssertTrue(activities.notifications.present(airPods()))
        XCTAssertTrue(activities.notifications.present(.lowBattery(level: 0.1)))
        XCTAssertEqual(activities.primary?.kind, .battery)
        XCTAssertEqual(activities.queueCount, 1)

        XCTAssertFalse(activities.notifications.present(volume(0.5)))
        XCTAssertEqual(activities.primary?.kind, .battery)
        XCTAssertEqual(activities.queueCount, 2)
        activities.notifications.dismiss()
        XCTAssertEqual(activities.primary?.kind, .audioDevice, "Unexpired lower priority resumes by rank")
        activities.notifications.dismiss()
        XCTAssertEqual(activities.primary?.kind, .systemHUD)
    }

    func testChargingAndLowBatteryShareOneBatteryActivity() {
        let activities = ActivityCoordinator(clock: clock())
        defer { activities.clearAll() }
        activities.notifications.present(.charging(level: 0.5))
        let id = activities.primary?.id
        activities.notifications.present(.lowBattery(level: 0.1))
        XCTAssertEqual(activities.liveActivities.count, 1)
        XCTAssertEqual(activities.primary?.id, id)
        XCTAssertEqual(activities.primary?.priority, .high)
    }

    func testEqualPriorityOrderingIsDeterministic() {
        let activities = ActivityCoordinator(clock: clock())
        defer { activities.clearAll() }
        activities.notifications.present(.charging(level: 0.5))
        activities.notifications.present(airPods())
        XCTAssertEqual(activities.primary?.kind, .audioDevice, "The latest equal-priority update presents")
        activities.notifications.present(.charging(level: 0.52))
        XCTAssertEqual(activities.primary?.kind, .charging, "A meaningful update is the latest event")
        activities.notifications.dismiss()
        XCTAssertEqual(activities.primary?.kind, .audioDevice)
    }

    // MARK: Coalescing

    func testSameStableActivityNeverDuplicates() {
        let activities = ActivityCoordinator(clock: clock())
        defer { activities.clearAll() }
        for level in stride(from: 0.1, through: 0.9, by: 0.1) { activities.notifications.present(volume(level)) }
        XCTAssertEqual(activities.liveActivities.count, 1)

        activities.notifications.present(reminder(.reminder30, event: "standup"))
        activities.notifications.present(reminder(.reminder5, event: "standup"))
        XCTAssertEqual(activities.liveActivities.filter { $0.kind == .calendar }.count, 1)
        XCTAssertEqual(activities.activeTransient?.priority, .high)

        var changes = 0
        activities.present(music())
        let observation = activities.$persistentActivity.dropFirst().sink { _ in changes += 1 }
        for _ in 0..<20 { activities.present(music()) }
        XCTAssertEqual(changes, 0, "Unchanged provider snapshots publish nothing")
        activities.present(music(playing: false))
        XCTAssertEqual(changes, 1)
        observation.cancel()
    }

    // MARK: Expiration

    func testUpdatedTransientResetsItsLifetimeAndStaleDeadlineCannotRemoveIt() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        defer { activities.clearAll() }
        activities.notifications.present(airPods("AirPods Pro"))
        await settle(clock)
        await clock.advance(by: .milliseconds(2400))
        // A newer generation of the same activity just before the first deadline.
        activities.notifications.present(airPods("AirPods Max"))
        let id = activities.primary?.id
        await settle(clock)
        await clock.advance(by: .milliseconds(100))
        await drain()
        XCTAssertEqual(activities.primary?.id, id, "The superseded 2.5 s deadline must not remove it")
        XCTAssertEqual(activities.notifications.expiresAt, base.addingTimeInterval(2.4 + 2.5))
        await clock.advance(by: .milliseconds(2400))
        await waitUntil { activities.primary == nil }
        XCTAssertNil(activities.primary)
    }

    func testInterruptedTransientResumesOnItsOriginalAbsoluteDeadline() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        defer { activities.clearAll() }
        activities.notifications.present(reminder())
        await settle(clock)
        let critical = NotchActivity(id: UUID(), kind: .notification, title: "Critical", subtitle: nil,
                                     priority: .critical, duration: nil)
        activities.present(critical)
        await clock.advance(by: .seconds(2))
        activities.dismiss(id: critical.id)
        XCTAssertEqual(activities.activeTransient?.kind, .calendar)
        XCTAssertEqual(activities.notifications.expiresAt, base.addingTimeInterval(5))
    }

    // MARK: Secondary / promotion

    func testOneSecondaryCoexistsAndPromotionPreservesUnderlyingActivities() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        defer { activities.clearAll() }
        activities.present(music())
        activities.notifications.present(.lowBattery(level: 0.1))
        XCTAssertEqual(activities.primary?.kind, .battery)
        XCTAssertEqual(activities.secondary?.id, musicID)

        activities.promoteSecondary()
        XCTAssertEqual(activities.primary?.id, musicID)
        XCTAssertEqual(activities.secondary?.kind, .battery, "The previous primary stays live as the secondary")
        XCTAssertNil(activities.notifications.active)
        XCTAssertEqual(activities.presentationMode, .mediaSides)
        XCTAssertEqual(activities.queueCount, 1)

        // Promotion changes the role back, never the identity.
        let batteryID = activities.secondary?.id
        activities.promoteSecondary()
        XCTAssertEqual(activities.primary?.id, batteryID)
        activities.promoteSecondary()
        XCTAssertEqual(activities.primary?.id, musicID)

        // A new event releases the promotion; natural ranking resumes (high battery > medium output).
        activities.notifications.present(airPods())
        XCTAssertEqual(activities.primary?.kind, .battery)
        XCTAssertEqual(activities.secondary?.kind, .audioDevice)
        // Only ever one secondary, even with three live activities.
        XCTAssertEqual(activities.liveActivities.count, 3)
        XCTAssertNotNil(activities.secondary)
    }

    func testPromotedActivityExpiringUnderneathLeavesNoStaleSecondary() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        defer { activities.clearAll() }
        activities.present(music())
        activities.notifications.present(.charging(level: 0.4))
        activities.promoteSecondary()
        XCTAssertEqual(activities.secondary?.kind, .charging)
        await settle(clock)
        await clock.advance(by: .milliseconds(2500))
        await waitUntil { activities.secondary == nil }
        XCTAssertEqual(activities.primary?.id, musicID)
        XCTAssertNil(activities.secondary)
    }

    func testSecondaryChipIsOnlyPresentedBesideVisibleCollapsedSideContent() {
        let model = DynamicIslandPresentationModel(clock: clock())
        let renderer = VisibleMediaRenderer()
        model.mediaRenderer = renderer
        defer { model.reset() }
        model.activityCoordinator.present(music())
        model.notificationCoordinator.present(airPods())
        XCTAssertEqual(model.presentedSecondary?.id, musicID)

        model.present(.expanded, animated: false)
        XCTAssertNil(model.presentedSecondary, "Expanded pages never show the chip")
        model.present(.collapsed, animated: false)

        model.notificationCoordinator.present(reminder())
        XCTAssertNil(model.presentedSecondary, "Calendar banners keep Music in the top row instead")
        model.activityCoordinator.dismiss(kind: .calendar)

        model.activityCoordinator.dismiss(kind: .audioDevice)
        model.notificationCoordinator.present(volume(0.3))
        XCTAssertNil(model.presentedSecondary)
    }

    // MARK: Navigation

    func testActivityChangesAndPromotionNeverOverrideManualPage() async {
        for page in NotchPage.allCases {
            let clock = clock()
            let model = DynamicIslandPresentationModel(clock: clock)
            model.present(.expanded, animated: false)
            model.pageModel.selectedPage = page
            var selections: [NotchPage] = []
            let observation = model.pageModel.$selectedPage.dropFirst().sink { selections.append($0) }
            model.activityCoordinator.present(music())
            model.notificationCoordinator.present(.lowBattery(level: 0.1))
            model.activateSecondaryActivity()
            model.notificationCoordinator.present(volume(0.5))
            model.notificationCoordinator.present(reminder())
            await settle(clock)
            await clock.advance(by: .seconds(10))
            await drain()
            model.activityCoordinator.dismiss(id: musicID)
            XCTAssertEqual(model.pageModel.selectedPage, page)
            XCTAssertTrue(selections.isEmpty, "\(page): \(selections)")
            observation.cancel()
            model.reset()
        }
    }

    // MARK: Restart

    func testRestartReconstructsPersistentMusicFromProviderAndDropsTransients() {
        let first = DynamicIslandPresentationModel(clock: clock())
        let firstMedia = MediaSessionController(provider: MockMediaProvider(), coordinator: first.activityCoordinator)
        firstMedia.receive(.init(connectionState: .authenticated, playbackState: .playing,
                                 title: "Track", trackID: "track", source: .spotify))
        first.showAudioHUD(.init(kind: .volume, deviceName: "Speakers", volume: 0.4, isMuted: false))
        XCTAssertEqual(first.activityCoordinator.liveActivities.count, 2)
        firstMedia.stop()
        first.reset()

        // Relaunch: nothing is replayed; Music comes only from current provider state.
        let second = DynamicIslandPresentationModel(clock: clock())
        XCTAssertTrue(second.activityCoordinator.liveActivities.isEmpty)
        let media = MediaSessionController(provider: MockMediaProvider(), coordinator: second.activityCoordinator)
        defer { media.stop(); second.reset() }
        media.receive(.init(connectionState: .authenticated, playbackState: .playing,
                            title: "Track", trackID: "track", source: .spotify))
        XCTAssertEqual(second.activityCoordinator.liveActivities.map(\.key), [.media])
        XCTAssertNil(second.activityCoordinator.activeTransient)
        XCTAssertEqual(second.activityCoordinator.preferredExpandedPage, .music)
    }

    // MARK: Lifecycle

    func testClearAllCancelsTheSingleLifetimeTask() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        activities.notifications.present(reminder())
        activities.notifications.present(airPods())
        activities.notifications.present(volume(0.2))
        await settle(clock)
        let running = await clock.pendingSleepCount()
        XCTAssertEqual(running, 1, "One lifetime task serves every transient")
        activities.clearAll()
        await drain()
        let remaining = await clock.pendingSleepCount()
        XCTAssertEqual(remaining, 0)
        XCTAssertNil(activities.notifications.active)
    }
}

@MainActor private final class VisibleMediaRenderer: NotchMediaRendering {
    var collapsedMediaVisible: Bool { true }
    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView { AnyView(Color.clear) }
    func expandedMedia() -> AnyView { AnyView(Color.clear) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(Color.clear) }
}
