import AppKit
import Foundation
import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
final class AirPodsSleepWakeTests: XCTestCase {
    func testSleepClearsTransientAudioFeedbackAcrossProjectionsAndPreservesOtherActivities() {
        let source = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        let firstDisplay = ActivityCoordinator(projecting: source)
        let secondDisplay = ActivityCoordinator(projecting: source)
        let media = activity(.media, lifetime: .persistent)
        let condition = activity(.audioDevice, lifetime: .condition)
        let calendar = activity(.calendar, duration: .seconds(3600))
        let volume = activity(.systemHUD, priority: .critical, duration: .seconds(2))
        source.present(media)
        source.present(condition)
        source.present(calendar)
        firstDisplay.notifications.present(.audio(disconnectedHUD))
        source.present(volume)
        XCTAssertTrue(source.liveActivities.contains { $0.kind == .audioDevice && !$0.lifetime.isBaseline })
        XCTAssertTrue(source.contains(id: volume.id))

        firstDisplay.setSystemSleeping(true)

        for coordinator in [source, firstDisplay, secondDisplay] {
            XCTAssertTrue(coordinator.contains(id: media.id))
            XCTAssertTrue(coordinator.contains(id: condition.id), "Provider-owned conditions survive sleep")
            XCTAssertTrue(coordinator.contains(id: calendar.id), "Calendar keeps its existing lifetime policy")
            XCTAssertFalse(coordinator.contains(id: volume.id))
            XCTAssertFalse(coordinator.liveActivities.contains {
                !$0.lifetime.isBaseline && ($0.kind == .audioDevice || $0.kind == .systemHUD)
            })
        }
        source.clearAll()
    }

    func testSleepingSourceRejectsAudioFromAllSubmissionPathsAndAcceptsProviderState() {
        let source = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        let display = ActivityCoordinator(projecting: source)
        display.setSystemSleeping(true)

        XCTAssertFalse(display.notifications.present(.audio(disconnectedHUD), refreshingLifetime: true))
        source.present(activity(.audioDevice, duration: .seconds(3)))
        display.present(activity(.systemHUD, duration: .seconds(2)))
        XCTAssertTrue(source.liveActivities.isEmpty)

        let media = activity(.media, lifetime: .persistent)
        let condition = activity(.audioDevice, lifetime: .condition)
        let calendar = activity(.calendar, duration: .seconds(3600))
        display.present(media)
        source.present(condition)
        display.present(calendar)
        XCTAssertEqual(Set(source.liveActivities.map(\.id)), Set([media.id, condition.id, calendar.id]))
        display.setSystemSleeping(false)
        XCTAssertEqual(Set(display.liveActivities.map(\.id)), Set([media.id, condition.id, calendar.id]))
        source.clearAll()
    }

    func testOvernightWakeCannotReplayDisconnectBeforeOldTimersResume() async {
        let clock = AirPodsSleepWakeClock()
        let panel = AirPodsSleepWakePanel()
        let coordinator = makeCoordinator(clock: clock, panel: panel)
        coordinator.start()
        defer { coordinator.stop() }
        let model = coordinator.presentationModel
        model.showAudioHUD(disconnectedHUD)
        await waitForSleepCount(1, clock: clock)
        XCTAssertNotNil(model.notificationCoordinator.active)

        post(NSWorkspace.screensDidSleepNotification)
        XCTAssertNil(panel.placement)
        XCTAssertNil(model.notificationCoordinator.active)
        await clock.advanceWallTime(by: .seconds(8 * 60 * 60))
        post(NSWorkspace.screensDidWakeNotification)

        // No sleeper has been released: recovery cannot depend on a timer callback winning
        // its race with WindowServer's wake notifications.
        XCTAssertNil(model.notificationCoordinator.active)
        XCTAssertNil(model.audioHUD)
        XCTAssertEqual(model.visualState, .collapsed)
        XCTAssertNotNil(panel.placement)
        XCTAssertTrue(panel.reconciliations.allSatisfy { !$0.hasAudioFeedback || !$0.isWake })
        coordinator.stop()
        await drainMainActorTasks()
        await clock.releaseAll()
        await drainMainActorTasks()
    }

    func testDisconnectBeforeDeadlineStampingIsDiscardedSynchronouslyOnSleep() async {
        let clock = AirPodsSleepWakeClock()
        let coordinator = makeCoordinator(clock: clock, panel: AirPodsSleepWakePanel())
        coordinator.start()
        defer { coordinator.stop() }
        let model = coordinator.presentationModel
        model.showAudioHUD(disconnectedHUD)
        XCTAssertNil(model.notificationCoordinator.expiresAt)

        post(NSWorkspace.willSleepNotification)
        model.showAudioHUD(disconnectedHUD)
        post(NSWorkspace.didWakeNotification)
        XCTAssertNil(model.audioHUD)
        XCTAssertNil(model.notificationCoordinator.active)
        await drainMainActorTasks()
        XCTAssertFalse(model.activityCoordinator.liveActivities.contains { $0.kind == .audioDevice })
        coordinator.stop()
        await drainMainActorTasks()
        await clock.releaseAll()
        await drainMainActorTasks()
    }

    func testAudioArrivingBetweenScreenAndSystemSleepNotificationsNeverReplays() async {
        let eventOrders: [[Notification.Name]] = [
            [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification],
            [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification]
        ]
        for sleepEvents in eventOrders {
            let clock = AirPodsSleepWakeClock()
            let coordinator = makeCoordinator(clock: clock, panel: AirPodsSleepWakePanel())
            coordinator.start()
            let model = coordinator.presentationModel
            post(sleepEvents[0])
            model.showAudioHUD(disconnectedHUD)
            post(sleepEvents[1])
            model.showAudioHUD(.init(kind: .outputChanged, deviceName: "Speakers", volume: 0.5, isMuted: false))
            model.showAudioHUD(.init(kind: .volume, deviceName: "Speakers", volume: 0.5, isMuted: false))
            XCTAssertFalse(model.activityCoordinator.liveActivities.contains {
                $0.kind == .audioDevice || $0.kind == .systemHUD
            })

            await clock.advanceWallTime(by: .seconds(8 * 60 * 60))
            post(NSWorkspace.didWakeNotification)
            post(NSWorkspace.screensDidWakeNotification)
            XCTAssertNil(model.notificationCoordinator.active)
            XCTAssertEqual(model.presentationState, .passive)
            coordinator.stop()
            await drainMainActorTasks()
            await clock.releaseAll()
            await drainMainActorTasks()
        }
    }

    func testSessionSettlesVisualStateOnSleepAndAgainBeforeWakeReconciliation() {
        let model = DynamicIslandPresentationModel(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        let panel = AirPodsSleepWakePanel()
        panel.model = model
        let session = NotchDisplaySession(model: model, panel: panel)
        let placement = NotchShellPlacement(display: builtInDisplay(), mode: .physicalNotch)
        session.update(placement: placement, context: .normal, configuration: .automatic, animated: false)
        model.setFileDragNearby(true)
        model.present(.expanded, animated: false)
        model.setHovered(true)
        model.setAuxiliaryInteractionPresented(true)
        let initialRevision = model.systemTransitionRevision

        session.sleep()

        XCTAssertGreaterThan(model.systemTransitionRevision, initialRevision)
        XCTAssertEqual(model.visualState, .collapsed)
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        XCTAssertFalse(model.isHeldAfterSystemPresentation)
        XCTAssertEqual(model.fileDrag, .idle)
        XCTAssertNil(panel.placement)
        let sleepRevision = model.systemTransitionRevision
        session.update(placement: placement, context: .normal, configuration: .automatic, animated: false)
        XCTAssertGreaterThan(model.systemTransitionRevision, sleepRevision)
        XCTAssertEqual(panel.reconciliations.last?.revision, model.systemTransitionRevision,
                       "The native panel must receive the settled revision before it returns")
        XCTAssertEqual(panel.reconciliations.last?.state, .collapsed)
        XCTAssertEqual(panel.context, .normal)
        session.stop()
    }

    func testSleepCancelsPendingHoverAndFreshPointerEntryWorksAfterWake() async {
        let clock = AirPodsSleepWakeClock()
        let model = DynamicIslandPresentationModel(clock: clock)
        model.setHovered(true)
        await waitForSleepCount(1, clock: clock)
        model.prepareForSystemSleep()
        model.prepareForSystemWake()
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(model.visualState, .collapsed)

        // Sleep clears pointer ownership, so the same physical location can begin a new entry.
        model.setHovered(true)
        await waitForSleepCount(1, clock: clock)
        await clock.advanceWallTime(by: .milliseconds(120))
        await clock.releaseDue()
        await waitUntil { model.visualState == .hovered }
        XCTAssertEqual(model.visualState, .hovered)
        model.reset()
        await drainMainActorTasks()
        await clock.releaseAll()
        await drainMainActorTasks()
    }

    func testLatePreSleepDeadlineCannotDismissFreshDisconnectAndNewLifetimeStillExpires() async throws {
        let clock = AirPodsSleepWakeClock()
        let coordinator = makeCoordinator(clock: clock, panel: AirPodsSleepWakePanel())
        coordinator.start()
        defer { coordinator.stop() }
        let model = coordinator.presentationModel
        model.showAudioHUD(disconnectedHUD)
        await waitForSleepCount(1, clock: clock)
        let oldID = try XCTUnwrap(model.notificationCoordinator.active?.id)
        post(NSWorkspace.willSleepNotification)
        await clock.advanceWallTime(by: .seconds(8 * 60 * 60))
        post(NSWorkspace.didWakeNotification)
        model.showAudioHUD(disconnectedHUD)
        await waitForSleepCount(3, clock: clock) // Old deadline, wake settling, fresh deadline.
        let freshID = try XCTUnwrap(model.notificationCoordinator.active?.id)
        XCTAssertNotEqual(freshID, oldID)

        await clock.releaseDue() // Deliberately deliver the cancelled pre-sleep callback late.
        await drainMainActorTasks()
        XCTAssertEqual(model.notificationCoordinator.active?.id, freshID)
        await clock.advanceWallTime(by: .milliseconds(2490))
        await clock.releaseDue()
        await drainMainActorTasks()
        XCTAssertEqual(model.notificationCoordinator.active?.id, freshID)
        await clock.advanceWallTime(by: .milliseconds(10))
        await clock.releaseDue()
        await waitUntil { model.notificationCoordinator.active == nil }
        XCTAssertNil(model.notificationCoordinator.active)
        coordinator.stop()
        await drainMainActorTasks()
        await clock.releaseAll()
        await drainMainActorTasks()
    }

    private var disconnectedHUD: NotchAudioHUD {
        .init(kind: .deviceDisconnected, deviceName: "AirPods Pro", volume: 0.5,
              isMuted: false, deviceID: "airpods-fixture")
    }

    private func activity(_ kind: NotchActivityKind, priority: NotchActivityPriority? = nil,
                          lifetime: NotchActivityLifetime? = nil, duration: Duration? = nil) -> NotchActivity {
        .init(id: UUID(), kind: kind, title: kind.rawValue, subtitle: nil, priority: priority,
              lifetime: lifetime, duration: duration)
    }

    private func makeCoordinator(clock: any AppClock, panel: AirPodsSleepWakePanel) -> NotchiumDisplayCoordinator {
        NotchiumDisplayCoordinator(clock: clock, displaySource: AirPodsSleepWakeDisplays(),
            panelControllerFactory: { model in panel.model = model; return panel })
    }

    private func post(_ name: Notification.Name) {
        NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
    }

    private func waitForSleepCount(_ count: Int, clock: AirPodsSleepWakeClock,
                                   file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<10_000 {
            if await clock.pendingCount() >= count { return }
            await Task.yield()
        }
        let actual = await clock.pendingCount()
        XCTFail("Expected at least \(count) sleepers; received \(actual)", file: file, line: line)
    }
}

@MainActor
private final class AirPodsSleepWakeDisplays: NotchiumDisplaySnapshotting {
    func snapshots() -> [NotchiumDisplaySnapshot] { [builtInDisplay()] }
}

@MainActor
private final class AirPodsSleepWakePanel: NotchPanelControlling {
    struct Reconciliation {
        let revision: Int
        let state: NotchStableState
        let hasAudioFeedback: Bool
        let isWake: Bool
    }
    weak var model: DynamicIslandPresentationModel?
    private(set) var placement: NotchShellPlacement?
    private(set) var context: NotchPresentationContext = .normal
    private(set) var reconciliations: [Reconciliation] = []
    private var hasSlept = false

    func reconcile(placement: NotchShellPlacement, layout: NotchPanelLayout,
                   renderConfiguration: NotchShellRenderConfiguration, animated: Bool) {
        self.placement = placement
        if let model {
            reconciliations.append(.init(revision: model.systemTransitionRevision, state: model.visualState,
                                         hasAudioFeedback: model.audioHUD != nil, isWake: hasSlept))
        }
    }
    func hide() { placement = nil }
    func orderFrontRegardless() {}
    func setPresentationContext(_ context: NotchPresentationContext) {
        self.context = context
        if context == .sleeping { hasSlept = true }
    }
}

/// Wall time and timer delivery are independent. Cancellation intentionally does not remove
/// sleepers, exercising the production generation/cancellation guards when old work arrives late.
private actor AirPodsSleepWakeClock: AppClock {
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, Never>
    }
    private var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
    private var sleepers: [UUID: Sleeper] = [:]

    func now() -> Date { currentDate }
    func sleep(for duration: Duration) async throws {
        await withCheckedContinuation { continuation in
            sleepers[UUID()] = .init(deadline: currentDate.addingTimeInterval(duration.timeInterval),
                                    continuation: continuation)
        }
    }
    func pendingCount() -> Int { sleepers.count }
    func advanceWallTime(by duration: Duration) {
        currentDate = currentDate.addingTimeInterval(duration.timeInterval)
    }
    func releaseDue() {
        let due = sleepers.filter { $0.value.deadline <= currentDate }
        due.keys.forEach { sleepers.removeValue(forKey: $0) }
        due.values.forEach { $0.continuation.resume() }
    }
    func releaseAll() {
        let pending = sleepers.values
        sleepers.removeAll()
        pending.forEach { $0.continuation.resume() }
    }
}
