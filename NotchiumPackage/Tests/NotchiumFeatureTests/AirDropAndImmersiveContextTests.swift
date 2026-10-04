import AppKit
import NotchiumCore
@testable import NotchiumDynamicIsland
@testable import NotchiumShelfFeature
import XCTest

/// AirDrop is a native external presentation inside the current open session; it is followed by
/// whatever Space change the system makes when its sheet goes away.
@MainActor
final class AirDropSessionTests: XCTestCase {
    func testShelfAirDropCancelOrCompleteKeepsShelfOpenThroughTheReturningSpaceChange() async throws {
        for (state, completed) in [(NotchStableState.hovered, false), (.hovered, true),
                                   (.expanded, false), (.expanded, true)] {
            let clock = ControlledAppClock()
            let model = DynamicIslandPresentationModel(phase: Self.phase(state), clock: clock)
            defer { model.reset() }
            model.pageModel.selectedPage = .shelf
            model.pageModel.shelfSection = .clipboard
            let sharing = NativeFileSharing()
            let service = try XCTUnwrap(NSSharingService(named: .sendViaAirDrop))
            model.setHovered(true)
            let session = sharing.begin(window: nil, interaction: model.auxiliaryInteractionHandler,
                                        returnsToOpenSession: true, service: service)
            model.setHovered(false) // Pointer travels to the sheet.
            XCTAssertTrue(model.consumePointerClickForAuxiliaryInteraction(), "Cancel/Send click belongs to the sheet")
            if completed { session.sharingService(service, didShareItems: []) }
            else { session.sharingService(service, didFailToShareItems: [], error: CocoaError(.userCancelled)) }
            // Dismissing the sheet returns the user to the Space they came from (e.g. a fullscreen app).
            model.prepareForSystemTransition()
            await drainMainActorTasks()
            XCTAssertFalse(model.isAuxiliaryInteractionPresented)
            XCTAssertEqual(model.visualState, state)
            XCTAssertEqual(model.pageModel.selectedPage, .shelf)
            XCTAssertEqual(model.pageModel.shelfSection, .clipboard, "Shelf view, and its selection, stay mounted")
            let sleepers = await clock.pendingCount()
            XCTAssertEqual(sleepers, 0, "Sheet dismissal is not a hover exit")
        }
    }

    func testPointerLeavingAndSpaceChangesWhileAirDropIsActiveNeverCollapse() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        defer { model.reset() }
        model.pageModel.selectedPage = .shelf
        model.setHovered(true)
        model.auxiliaryInteractionHandler.beginNativeSharing(in: nil, source: "airdrop")
        for _ in 0..<20 {
            model.setHovered(false)
            model.prepareForSystemTransition()
            model.setHovered(true)
        }
        model.setHovered(false)
        await drainMainActorTasks()
        let sleepers = await clock.pendingCount()
        XCTAssertEqual(sleepers, 0)
        XCTAssertEqual(model.visualState, .hovered)
        XCTAssertEqual(model.pageModel.selectedPage, .shelf)
        XCTAssertTrue(model.isAuxiliaryInteractionPresented)
        model.auxiliaryInteractionHandler.endNativeSharing(in: nil, source: "airdrop", returnsToOpenSession: true)
    }

    func testAfterAirDropHoverCloseResumesAtTheNextRealPointerBoundary() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        defer { model.reset() }
        let interaction = model.auxiliaryInteractionHandler
        interaction.beginNativeSharing(in: nil, source: "airdrop")
        interaction.endNativeSharing(in: nil, source: "airdrop", returnsToOpenSession: true)
        XCTAssertTrue(model.isHeldAfterSystemPresentation)
        model.setHovered(true)
        XCTAssertFalse(model.isHeldAfterSystemPresentation, "Pointer entry hands the session back to hover")
        model.setHovered(false)
        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await waitUntil { model.visualState == .collapsed }
        XCTAssertEqual(model.visualState, .collapsed)
    }

    func testHeldSessionClosesOnOutsideClickLikeAPinnedOne() async {
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: ControlledAppClock())
        defer { model.reset() }
        XCTAssertFalse(model.collapsesOnOutsideClick, "A hovered shell follows the pointer, not clicks")
        let interaction = model.auxiliaryInteractionHandler
        interaction.beginNativeSharing(in: nil, source: "airdrop")
        interaction.endNativeSharing(in: nil, source: "airdrop", returnsToOpenSession: true)
        XCTAssertFalse(model.consumePointerClickForAuxiliaryInteraction())
        XCTAssertTrue(model.collapsesOnOutsideClick)
        model.collapse()
        XCTAssertFalse(model.isHeldAfterSystemPresentation)
        XCTAssertFalse(model.collapsesOnOutsideClick)
    }

    func testShareCancelWithoutAirDropStillFollowsHoverExit() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        defer { model.reset() }
        model.auxiliaryInteractionHandler.beginNativeSharing(in: nil, source: "share")
        model.setHovered(true)
        model.setHovered(false)
        model.auxiliaryInteractionHandler.endNativeSharing(in: nil, source: "share")
        XCTAssertFalse(model.isHeldAfterSystemPresentation)
        await waitForPendingSleep(clock)
        await clock.releaseAll()
        await waitUntil { model.visualState == .collapsed }
        XCTAssertEqual(model.visualState, .collapsed)
    }

    func testLateCallbackFromAnEarlierPresentationCannotEndTheCurrentOne() throws {
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: ControlledAppClock())
        defer { model.reset() }
        let sharing = NativeFileSharing()
        let service = try XCTUnwrap(NSSharingService(named: .sendViaAirDrop))
        for _ in 0..<10 {
            let first = sharing.begin(window: nil, interaction: model.auxiliaryInteractionHandler,
                                      returnsToOpenSession: true, service: service)
            first.sharingService(service, didFailToShareItems: [], error: CocoaError(.userCancelled))
            let second = sharing.begin(window: nil, interaction: model.auxiliaryInteractionHandler,
                                       returnsToOpenSession: true, service: service)
            first.sharingService(service, didShareItems: [])
            first.sharingService(service, didFailToShareItems: [], error: CocoaError(.userCancelled))
            XCTAssertTrue(model.isAuxiliaryInteractionPresented, "Presentation A's late callback is ignored")
            XCTAssertTrue(sharing.isActive)
            second.sharingService(service, didShareItems: [])
            XCTAssertFalse(model.isAuxiliaryInteractionPresented)
            XCTAssertFalse(sharing.isActive)
        }
        // Lease identities are independent at the model boundary too.
        let interaction = model.auxiliaryInteractionHandler
        interaction.beginNativeSharing(in: nil, source: "native.share.B")
        interaction.endNativeSharing(in: nil, source: "native.share.A", returnsToOpenSession: true)
        XCTAssertTrue(model.isAuxiliaryInteractionPresented)
        interaction.endNativeSharing(in: nil, source: "native.share.B", returnsToOpenSession: true)
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
    }

    private static func phase(_ state: NotchStableState) -> NotchPresentationPhase {
        state == .expanded ? .expanded : .hovered
    }
}

@MainActor
final class ImmersiveContextClassificationTests: XCTestCase {
    func testOneNormalizedContextFromDisplayScopedEvidence() {
        var state = DisplayPresentationState()
        let builtIn = builtInDisplay()
        var evidence = DisplayInteractionEvidence(frontmostDisplayID: builtIn.id)
        state.rebuild([builtIn], evidence: evidence)
        XCTAssertEqual(state.presentationContext, .normal)
        evidence.fullscreenDisplayID = builtIn.id
        evidence.isFullscreen = true
        state.resolve(evidence)
        XCTAssertEqual(state.presentationContext, .fullscreenApp)
        evidence.isImmersiveMedia = true
        state.resolve(evidence)
        XCTAssertEqual(state.presentationContext, .immersiveMedia)
        evidence.isPresentationLike = true
        state.resolve(evidence)
        XCTAssertEqual(state.presentationContext, .presentationLike, "Presentation is the strongest context")
        state.resolve(DisplayInteractionEvidence(frontmostDisplayID: builtIn.id))
        XCTAssertEqual(state.presentationContext, .normal, "Leaving fullscreen restores normal policy")
    }

    func testPlaybackOnlyMakesAFullscreenAppImmersive() {
        let display = builtInDisplay()
        let window = [CGRect(x: 0, y: 0, width: display.frame.width, height: display.frame.height)]
        let fullscreen = AppKitDisplayEnvironmentSource.project(
            options: [.fullScreen, .autoHideMenuBar, .autoHideDock], quartzFrames: window,
            pointerLocation: nil, displays: [display], frontmostPreventsDisplaySleep: false)
        XCTAssertTrue(fullscreen.isFullscreen)
        XCTAssertFalse(fullscreen.isImmersiveMedia)
        let video = AppKitDisplayEnvironmentSource.project(
            options: [.fullScreen, .autoHideMenuBar, .autoHideDock], quartzFrames: window,
            pointerLocation: nil, displays: [display], frontmostPreventsDisplaySleep: true)
        XCTAssertTrue(video.isImmersiveMedia)
        let windowedVideo = AppKitDisplayEnvironmentSource.project(
            options: [], quartzFrames: window, pointerLocation: nil, displays: [display],
            frontmostPreventsDisplaySleep: true)
        XCTAssertFalse(windowedVideo.isImmersiveMedia, "Windowed playback is ordinary desktop use")
    }

    func testAssertionReadIsConservativeForAProcessWithoutAssertions() {
        XCTAssertFalse(AppKitDisplayEnvironmentSource.preventsDisplaySleep(pid: -1))
    }
}

@MainActor
final class ImmersiveSurfacingPolicyTests: XCTestCase {
    private let routine: [NotchNotification.Kind] = [.outputDeviceChanged, .charging, .powerDisconnected,
                                                      .screenshot, .focusModeChanged]
    private let ambient: [NotchNotification.Kind] = [.lowBattery, .reminder30, .reminder60]
    private let essential: [NotchNotification.Kind] = [.criticalBattery, .reminder5, .transferFinished,
                                                        .transferFailed, .focusTimerComplete, .volume, .mute,
                                                        .actionSucceeded, .actionFailed, .reminderAdded, .shelfAdded]

    func testPolicyPerContext() {
        let expectations: [(NotchPresentationContext, Set<Int>)] = [
            (.normal, [0, 1, 2]), (.fullscreenApp, [0, 1, 2]), (.immersiveMedia, [1, 2]), (.presentationLike, [2]),
        ]
        for (context, surfacingTiers) in expectations {
            for (tier, kinds) in [routine, ambient, essential].enumerated() {
                for kind in kinds {
                    let notice = NotchNotification.feedback("Fixture", kind: kind, key: "fixture")
                    XCTAssertEqual(ActivitySurfacingPolicy.shouldSurface(notice.activity, notificationKind: kind, in: context),
                                   surfacingTiers.contains(tier), "\(kind) in \(context)")
                }
            }
            let brightness = NotchActivity(id: UUID(), kind: .systemHUD, title: "Brightness", subtitle: nil, duration: nil)
            XCTAssertTrue(ActivitySurfacingPolicy.shouldSurface(brightness, in: context), "User keys always answer")
        }
    }

    func testImmersiveMediaQuietsRoutineButCriticalAndUserTriggeredSurface() {
        let coordinator = ActivityCoordinator(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
        defer { coordinator.clearAll() }
        coordinator.setPresentationContext(.immersiveMedia)
        let charging = NotchNotification.charging(level: 0.5)
        coordinator.notifications.present(charging)
        XCTAssertNil(coordinator.primary)
        XCTAssertTrue(coordinator.contains(id: charging.id), "Quiet, never dropped from the provider's view")
        for context in [NotchPresentationContext.immersiveMedia, .presentationLike] {
            coordinator.setPresentationContext(context)
            let critical = NotchNotification.feedback("Battery 3%", kind: .criticalBattery, key: "battery.critical")
            coordinator.notifications.present(critical)
            XCTAssertEqual(coordinator.primary?.id, critical.id)
            coordinator.dismissActive()
            let action = NotchNotification.feedback("Copied", kind: .actionSucceeded, key: "action.fixture")
            coordinator.notifications.present(action)
            XCTAssertEqual(coordinator.primary?.id, action.id)
            coordinator.dismissActive()
        }
    }

    func testPersistentActivitiesSurviveEveryContextTransitionWithTheirIdentity() {
        let coordinator = ActivityCoordinator(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
        defer { coordinator.clearAll() }
        let music = NotchActivity(id: UUID(), kind: .media, title: "Song", subtitle: nil,
                                  lifetime: .persistent, duration: nil, minimal: .progress(0.2))
        let transfer = NotchActivity(id: UUID(), kind: .download, title: "File", subtitle: nil,
                                     lifetime: .persistent, duration: nil, minimal: .progress(0.5))
        coordinator.present(music)
        coordinator.present(transfer)
        let normal = coordinator.primary?.id
        XCTAssertNotNil(normal)
        for context in [NotchPresentationContext.fullscreenApp, .immersiveMedia] {
            coordinator.setPresentationContext(context)
            XCTAssertEqual(coordinator.primary?.id, normal, "Fullscreen and video keep ongoing state visible")
        }
        coordinator.setPresentationContext(.presentationLike)
        XCTAssertNil(coordinator.primary, "Presenting keeps ongoing state quiet")
        XCTAssertTrue(coordinator.contains(id: music.id))
        XCTAssertTrue(coordinator.contains(id: transfer.id))
        coordinator.setPresentationContext(.normal)
        XCTAssertEqual(coordinator.primary?.id, normal)
        XCTAssertEqual(Set(coordinator.liveActivities.map(\.id)), [music.id, transfer.id])
    }
}

@MainActor
private final class ContextDisplays: NotchiumDisplaySnapshotting {
    var displays = [builtInDisplay()]
    func snapshots() -> [NotchiumDisplaySnapshot] { displays }
}

@MainActor
private final class ContextEnvironment: DisplayEnvironmentReading {
    var value = DisplayInteractionEvidence()
    var reads = 0
    var callbacks: [@MainActor () -> Void] = []
    var pointerLocation: CGPoint? { value.pointerLocation }
    func evidence(displays: [NotchiumDisplaySnapshot]) -> DisplayInteractionEvidence { reads += 1; return value }
    func start(onChange: @escaping @MainActor () -> Void) { callbacks.append(onChange) }
    func stop() {}
}

@MainActor
private final class ContextPanel: NotchPanelControlling {
    var placements: [NotchShellPlacement] = []
    var context: NotchPresentationContext = .normal
    func reconcile(placement: NotchShellPlacement, layout: NotchPanelLayout,
                   renderConfiguration: NotchShellRenderConfiguration, animated: Bool) { placements.append(placement) }
    func hide() {}
    func orderFrontRegardless() {}
    func setPresentationContext(_ context: NotchPresentationContext) { self.context = context }
}

@MainActor
final class ImmersiveContextCoordinatorTests: XCTestCase {
    func testRapidSpaceAndOptionEventsSettleOnCurrentTruthNotAStaleContext() async {
        let environment = ContextEnvironment(), panel = ContextPanel(), clock = ControlledAppClock()
        let coordinator = NotchiumDisplayCoordinator(clock: clock, displaySource: ContextDisplays(),
            environmentSource: environment, panelControllerFactory: { _ in panel })
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.presentationModel.present(.expanded, animated: false)
        coordinator.presentationModel.pageModel.selectedPage = .pomodoro
        environment.value.frontmostDisplayID = NotchiumDisplayID(rawValue: 1)
        let sequence: [(fullscreen: Bool, immersive: Bool, presenting: Bool)] = [
            (true, false, false), (true, true, false), (false, false, false), (true, true, true), (true, true, false),
        ]
        for step in sequence {
            environment.value.isFullscreen = step.fullscreen
            environment.value.isImmersiveMedia = step.immersive
            environment.value.isPresentationLike = step.presenting
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            environment.callbacks.last?()
        }
        for _ in 0..<10_000 where panel.context != .immersiveMedia {
            await clock.releaseAll()
            await Task.yield()
        }
        XCTAssertEqual(panel.context, .immersiveMedia)
        XCTAssertEqual(coordinator.presentationModel.activityCoordinator.presentationContext, .immersiveMedia)
        XCTAssertEqual(coordinator.presentationModel.visualState, .expanded, "Context changes never close the shell")
        XCTAssertEqual(coordinator.presentationModel.pageModel.selectedPage, .pomodoro)
        XCTAssertEqual(panel.placements.last?.display.id.rawValue, 1)
    }

    func testPlaybackStartedInsideFullscreenIsReadWhenAnActivityArrives() {
        let environment = ContextEnvironment(), panel = ContextPanel()
        let coordinator = NotchiumDisplayCoordinator(clock: TestAppClock(now: Date(), automaticallyAdvances: false),
            displaySource: ContextDisplays(), environmentSource: environment, panelControllerFactory: { _ in panel })
        environment.value.frontmostDisplayID = NotchiumDisplayID(rawValue: 1)
        environment.value.isFullscreen = true
        coordinator.start()
        defer { coordinator.stop() }
        XCTAssertEqual(panel.context, .fullscreenApp)
        // No Space, activation or option change accompanies pressing Play.
        environment.value.isImmersiveMedia = true
        let activities = coordinator.presentationModel.activityCoordinator
        let unplugged = NotchNotification.feedback("Unplugged", kind: .powerDisconnected, key: "battery")
        activities.notifications.present(unplugged)
        XCTAssertEqual(panel.context, .immersiveMedia)
        XCTAssertNil(activities.primary)
        XCTAssertTrue(activities.contains(id: unplugged.id))
        // Desktop submissions keep the cheap pointer-only refresh.
        environment.value = DisplayInteractionEvidence(frontmostDisplayID: NotchiumDisplayID(rawValue: 1))
        coordinator.refreshDisplayConfiguration()
        let reads = environment.reads
        activities.notifications.present(NotchNotification.feedback("Copied", kind: .actionSucceeded, key: "action"))
        XCTAssertEqual(environment.reads, reads)
        activities.clearAll()
    }

    func testPanelLevelIsDerivedFromCurrentOwnersAcrossEveryContext() {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { panel.close() }
        panel.applyNotchWindowBehavior()
        for context in [NotchPresentationContext.fullscreenApp, .immersiveMedia, .presentationLike, .normal] {
            panel.setPresentationContext(context)
            XCTAssertEqual(panel.level, NotchPanel.restingLevel)
            panel.setNativeSharingPresented(true, source: "airdrop")
            XCTAssertEqual(panel.level, .floating)
            panel.setNativeSharingPresented(false, source: "airdrop")
            XCTAssertEqual(panel.level, NotchPanel.restingLevel, "No level is saved across a Space/context change")
            XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        }
    }
}
