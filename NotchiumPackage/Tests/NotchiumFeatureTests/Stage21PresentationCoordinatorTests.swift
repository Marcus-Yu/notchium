import AppKit
import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
private final class Stage21Displays: NotchiumDisplaySnapshotting {
    var displays = [builtInDisplay()]
    var reads = 0
    func snapshots() -> [NotchiumDisplaySnapshot] { reads += 1; return displays }
}

@MainActor
private final class Stage21Environment: DisplayEnvironmentReading {
    var value = DisplayInteractionEvidence()
    var pointerLocation: CGPoint? { value.pointerLocation }
    var reads = 0
    var callbacks: [@MainActor () -> Void] = []
    var stops = 0
    func evidence(displays: [NotchiumDisplaySnapshot]) -> DisplayInteractionEvidence { reads += 1; return value }
    func start(onChange: @escaping @MainActor () -> Void) { callbacks.append(onChange) }
    func stop() { stops += 1 }
}

@MainActor
private final class Stage21Panel: NotchPanelControlling {
    var layouts: [NotchPanelLayout] = []
    var hides = 0
    var reassertions = 0
    var context: NotchPresentationContext = .normal
    var interaction: (@MainActor (CGPoint) -> Void)?
    func reconcile(placement: NotchShellPlacement, layout: NotchPanelLayout,
                   renderConfiguration: NotchShellRenderConfiguration, animated: Bool) { layouts.append(layout) }
    func hide() { hides += 1 }
    func orderFrontRegardless() { reassertions += 1 }
    func setPresentationContext(_ context: NotchPresentationContext) { self.context = context }
    func setInteractionHandler(_ handler: (@MainActor (CGPoint) -> Void)?) { interaction = handler }
}

/// Deliberately non-cooperative: releasing old work must still be rejected by its generation.
private actor Stage21LateClock: AppClock {
    var sleeps: [CheckedContinuation<Void, Never>] = []
    func now() -> Date { Date(timeIntervalSince1970: 0) }
    func sleep(for duration: Duration) async throws {
        await withCheckedContinuation { sleeps.append($0) }
    }
    func count() -> Int { sleeps.count }
    func releaseAll() {
        let pending = sleeps
        sleeps.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class Stage21PresentationCoordinatorTests: XCTestCase {
    func testTopologyMigrationPreservesEveryOpenPageAndOnePanelFactory() async {
        let source = Stage21Displays(), environment = Stage21Environment(), panel = Stage21Panel()
        var creations = 0
        let coordinator = NotchiumDisplayCoordinator(clock: TestAppClock(now: Date(), automaticallyAdvances: false),
            displaySource: source, environmentSource: environment, panelControllerFactory: { _ in creations += 1; return panel })
        coordinator.start()
        defer { coordinator.stop() }
        let model = coordinator.presentationModel
        let external = externalDisplay(id: 2, frame: CGRect(x: 1512, y: -100, width: 1920, height: 1080))
        for page in [NotchPage.shelf, .music, .pomodoro] {
            model.present(.expanded, animated: false)
            model.pageModel.selectedPage = page
            model.pageModel.shelfSection = .clipboard
            let media = NotchActivity(id: UUID(), kind: .media, title: "Fixture", subtitle: nil, duration: nil)
            model.activityCoordinator.present(media)
            source.displays = [external] // Owned built-in removed / clamshell.
            coordinator.refreshDisplayConfiguration()
            XCTAssertEqual(coordinator.displayState.ownedDisplayID, external.id)
            XCTAssertNil(coordinator.shellPlacement)
            XCTAssertEqual(model.visualState, .expanded)
            XCTAssertEqual(model.pageModel.selectedPage, page)
            XCTAssertTrue(model.pageModel.manualSelectionDuringExpansion)
            XCTAssertEqual(model.pageModel.shelfSection, .clipboard)
            XCTAssertTrue(model.activityCoordinator.contains(id: media.id))
            source.displays = [builtInDisplay(), external]
            coordinator.refreshDisplayConfiguration()
            coordinator.claimDisplay(NotchiumDisplayID(rawValue: 1))
            XCTAssertNotNil(coordinator.shellPlacement)
            XCTAssertEqual(model.pageModel.selectedPage, page)
            XCTAssertTrue(model.pageModel.manualSelectionDuringExpansion)
        }
        XCTAssertEqual(creations, 1)
        // A genuinely new open session still runs the existing automatic-page resolver.
        model.activityCoordinator.clearAll()
        model.present(.collapsed, animated: false)
        model.present(.expanded, animated: false)
        XCTAssertEqual(model.pageModel.selectedPage, .home)
        XCTAssertFalse(model.pageModel.manualSelectionDuringExpansion)
        await drainMainActorTasks()
    }

    func testPassiveActivityFollowsPointerButPinnedAndSharingOwnershipWins() {
        let source = Stage21Displays(), environment = Stage21Environment(), panel = Stage21Panel()
        let external = externalDisplay(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        source.displays.append(external)
        let coordinator = make(source, environment, panel)
        coordinator.start()
        defer { coordinator.stop() }
        let model = coordinator.presentationModel
        environment.value.pointerLocation = CGPoint(x: 1800, y: 500)
        model.activityCoordinator.present(.init(id: UUID(), kind: .systemHUD, title: "Brightness", subtitle: nil, duration: nil))
        XCTAssertEqual(coordinator.displayState.ownedDisplayID, external.id)
        coordinator.claimDisplay(NotchiumDisplayID(rawValue: 1))
        model.present(.expanded, animated: false)
        model.pageModel.selectedPage = .shelf
        model.setAuxiliaryInteractionPresented(true, source: "share")
        model.activityCoordinator.present(.init(id: UUID(), kind: .calendar, title: "Calendar", subtitle: nil, duration: nil))
        XCTAssertEqual(coordinator.displayState.ownedDisplayID?.rawValue, 1)
        XCTAssertEqual(model.pageModel.selectedPage, .shelf)
        model.setAuxiliaryInteractionPresented(false, source: "share")
    }

    func testRapidEventsCoalesceWithoutGeometryOrTopologyWorkWhenUnchanged() async {
        let source = Stage21Displays(), environment = Stage21Environment(), panel = Stage21Panel()
        let clock = ControlledAppClock()
        let coordinator = make(source, environment, panel, clock: clock)
        coordinator.start()
        defer { coordinator.stop() }
        let initialLayouts = panel.layouts.count
        for _ in 0..<100 {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            environment.callbacks.last?()
        }
        await settle(clock, until: { panel.reassertions == 1 })
        XCTAssertEqual(environment.reads, 2)
        XCTAssertEqual(source.reads, 1, "Space/KVO events never rescan NSScreen topology")
        XCTAssertEqual(panel.layouts.count, initialLayouts)
        for _ in 0..<100 {
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
        await settle(clock, until: { source.reads == 2 })
        XCTAssertEqual(source.reads, 2)
        XCTAssertEqual(panel.layouts.count, initialLayouts)
        let generation = coordinator.displayState.topologyGeneration
        coordinator.refreshDisplayConfiguration()
        XCTAssertEqual(coordinator.displayState.topologyGeneration, generation)
    }

    func testOldWorkCannotReconcileAfterManualSelectionSleepOrRestart() async {
        let source = Stage21Displays(), environment = Stage21Environment(), panel = Stage21Panel()
        let clock = Stage21LateClock()
        let coordinator = make(source, environment, panel, clock: clock)
        coordinator.start()
        coordinator.scheduleReconciliation(topology: true)
        for _ in 0..<1000 { if await clock.count() > 0 { break }; await Task.yield() }
        coordinator.claimDisplay(NotchiumDisplayID(rawValue: 1))
        let reads = source.reads // Explicit selection consumes any pending topology rebuild.
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(source.reads, reads)
        coordinator.scheduleReconciliation(topology: true)
        for _ in 0..<1000 { if await clock.count() > 0 { break }; await Task.yield() }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertEqual(coordinator.displayState.presentationContext, .sleeping)
        let layouts = panel.layouts.count
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertEqual(panel.layouts.count, layouts)
        coordinator.stop()
        coordinator.start()
        let freshReads = environment.reads
        environment.callbacks[0]() // A source callback already queued before stop/restart.
        await drainMainActorTasks()
        XCTAssertEqual(environment.reads, freshReads)
        let count = await clock.count()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(coordinator.displayState.presentationContext, .normal)
        coordinator.stop()
    }

    func testContextKVOAndWakeUseCurrentEvidenceAndPreservePinnedPage() async {
        let source = Stage21Displays(), environment = Stage21Environment(), panel = Stage21Panel()
        let clock = ControlledAppClock()
        let coordinator = make(source, environment, panel, clock: clock)
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.presentationModel.present(.expanded, animated: false)
        coordinator.presentationModel.pageModel.selectedPage = .music
        environment.value.frontmostDisplayID = NotchiumDisplayID(rawValue: 1)
        for context in [NotchPresentationContext.fullscreenApp, .presentationLike, .normal] {
            environment.value.isFullscreen = context == .fullscreenApp
            environment.value.isPresentationLike = context == .presentationLike
            environment.callbacks.last?()
            await waitForPendingSleep(clock)
            await clock.releaseAll()
            await waitUntil { panel.context == context }
            XCTAssertEqual(panel.context, context)
            XCTAssertEqual(coordinator.presentationModel.pageModel.selectedPage, .music)
            XCTAssertEqual(coordinator.presentationModel.visualState, .expanded)
        }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        environment.value.isFullscreen = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(panel.context, .fullscreenApp)
        XCTAssertFalse(coordinator.displayState.sleeping)
        XCTAssertEqual(coordinator.presentationModel.visualState, .collapsed, "Wake cannot reopen the previous session")
    }

    func testNativePanelLevelsRemainDerivedFromOverlappingCurrentOwners() {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { panel.close() }
        panel.applyNotchWindowBehavior()
        for _ in 0..<100 {
            panel.setAcceptsFileDrags(true)
            panel.setNativeSharingPresented(true, source: "share")
            panel.setPresentationContext(.fullscreenApp)
            panel.setNativeSharingPresented(true, source: "airdrop")
            panel.setNativeSharingPresented(false, source: "share")
            panel.setPresentationContext(.sleeping)
            panel.setPresentationContext(.presentationLike)
            XCTAssertEqual(panel.level, .floating)
            panel.setNativeSharingPresented(false, source: "airdrop")
            XCTAssertEqual(panel.level, NotchPanel.fileDragLevel)
            panel.setPresentationContext(.normal)
            panel.setAcceptsFileDrags(false)
            XCTAssertEqual(panel.level, NotchPanel.restingLevel)
        }
    }

    /// Advance controlled sleepers until the event's observable result, including a newer
    /// coalescer registered while cancellation of the preceding request is still draining.
    private func settle(_ clock: ControlledAppClock, until condition: @MainActor () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await clock.releaseAll()
            await Task.yield()
        }
    }

    private func make(_ source: Stage21Displays, _ environment: Stage21Environment, _ panel: Stage21Panel,
                      clock: any AppClock = TestAppClock(now: Date(), automaticallyAdvances: false)) -> NotchiumDisplayCoordinator {
        NotchiumDisplayCoordinator(clock: clock, displaySource: source, environmentSource: environment,
                                  panelControllerFactory: { _ in panel })
    }
}
