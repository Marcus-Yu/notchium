import AppKit
import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
private final class MultipleDisplaySource: NotchiumDisplaySnapshotting {
    var displays = [externalDisplay(id: 2, frame: CGRect(x: -1920, y: 200, width: 1920, height: 1080)),
                    builtInDisplay(primary: false)]
    func snapshots() -> [NotchiumDisplaySnapshot] { displays }
}

@MainActor
private final class MultipleDisplayEnvironment: DisplayEnvironmentReading {
    var value = DisplayInteractionEvidence()
    var pointerLocation: CGPoint? { value.pointerLocation }
    func evidence(displays: [NotchiumDisplaySnapshot]) -> DisplayInteractionEvidence { value }
    func start(onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
}

@MainActor
private final class MultipleDisplayPanel: NotchPanelControlling {
    var placement: NotchShellPlacement?
    var layout: NotchPanelLayout?
    var hides = 0
    var reconciliations = 0
    var focuses = 0
    func reconcile(placement: NotchShellPlacement, layout: NotchPanelLayout,
                   renderConfiguration: NotchShellRenderConfiguration, animated: Bool) {
        self.placement = placement
        self.layout = layout
        reconciliations += 1
    }
    func hide() { placement = nil; layout = nil; hides += 1 }
    func orderFrontRegardless() {}
    func focusExpandedPanel() { focuses += 1 }
}

@MainActor
final class MultipleDisplayTests: XCTestCase {
    func testDefaultKeepsPlayingActivityAtBuiltInNotchWhenPointerAndPrimaryAreExternal() throws {
        let source = MultipleDisplaySource(), environment = MultipleDisplayEnvironment()
        environment.value.pointerLocation = CGPoint(x: -1000, y: 500)
        environment.value.frontmostDisplayID = source.displays[0].id
        let coordinator = make(source: source, environment: environment)
        coordinator.start()
        defer { coordinator.stop() }
        let music = NotchActivity(id: UUID(), kind: .media, title: "Playing", subtitle: nil, duration: nil)
        coordinator.presentationModel.activityCoordinator.present(music)
        XCTAssertEqual(coordinator.shellPlacements.count, 1)
        XCTAssertEqual(coordinator.shellPlacement?.display.id.rawValue, 1)
        XCTAssertEqual(coordinator.shellPlacement?.mode, .physicalNotch)
        XCTAssertEqual(coordinator.presentationModel.activityCoordinator.primary?.id, music.id)
        XCTAssertEqual(coordinator.presentationModel.activityCoordinator.presentationMode, .mediaSides)
    }

    func testAllDisplaysHaveIndependentExpansionHoverAndNavigation() async throws {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let settings = NotchDisplaySettings()
        settings.preferences.selection = .all
        var panels: [MultipleDisplayPanel] = []
        let coordinator = make(clock: clock, settings: settings, panels: { panels.append($0) })
        coordinator.start()
        defer { coordinator.stop() }
        let builtIn = try XCTUnwrap(coordinator.presentationModel(for: .init(rawValue: 1)))
        let external = try XCTUnwrap(coordinator.presentationModel(for: .init(rawValue: 2)))
        XCTAssertFalse(builtIn === external)
        XCTAssertEqual(panels.count, 2)
        XCTAssertEqual(panels[0].placement?.mode, .physicalNotch)
        XCTAssertEqual(panels[1].placement?.mode, .virtualPill)

        builtIn.present(.expanded, animated: false)
        builtIn.pageModel.selectedPage = .music
        await waitUntil { panels[0].layout?.surfaceSize == ExpandedNotchLayout.size }
        XCTAssertEqual(external.visualState, .collapsed)
        XCTAssertEqual(panels[1].layout?.surfaceSize, CGSize(width: 180, height: 24))
        external.setHovered(true)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(120))
        await waitUntil { external.visualState == .hovered }
        XCTAssertEqual(external.visualState, .hovered)
        XCTAssertEqual(builtIn.visualState, .expanded)
        external.pageModel.selectedPage = .audio
        XCTAssertEqual(builtIn.pageModel.selectedPage, .music)
        external.present(.collapsed, animated: false)
        XCTAssertEqual(builtIn.visualState, .expanded)
        XCTAssertEqual(panels.count, 2)
    }

    func testActivityIdentityDismissalAndDeadlineAreSharedAcrossDisplayProjections() async throws {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let settings = NotchDisplaySettings()
        settings.preferences.selection = .all
        let coordinator = make(clock: clock, settings: settings)
        coordinator.start()
        defer { coordinator.stop() }
        let builtIn = coordinator.presentationModel
        let external = try XCTUnwrap(coordinator.presentationModel(for: .init(rawValue: 2)))
        builtIn.notificationCoordinator.present(.charging(level: 80))
        await clock.waitForPendingSleeps()
        XCTAssertEqual(builtIn.notificationCoordinator.active?.id, external.notificationCoordinator.active?.id)
        XCTAssertEqual(builtIn.notificationCoordinator.expiresAt, external.notificationCoordinator.expiresAt)
        let sleeps = await clock.pendingSleepCount()
        XCTAssertEqual(sleeps, 1, "Displays must not duplicate activity expiry timers")
        let deadline = try XCTUnwrap(builtIn.notificationCoordinator.expiresAt)
        let now = await clock.now()
        await clock.advance(by: .seconds(deadline.timeIntervalSince(now)))
        await waitUntil { builtIn.notificationCoordinator.active == nil }
        XCTAssertNil(external.notificationCoordinator.active)
        builtIn.notificationCoordinator.present(.charging(level: 70))
        external.notificationCoordinator.dismissByUser()
        XCTAssertNil(builtIn.notificationCoordinator.active)
        XCTAssertNil(external.notificationCoordinator.active)
    }

    func testFullscreenPolicyIsLocalToEachDisplay() throws {
        let settings = NotchDisplaySettings()
        settings.preferences.selection = .all
        let environment = MultipleDisplayEnvironment()
        environment.value.fullscreenDisplayID = .init(rawValue: 2)
        environment.value.isFullscreen = true
        environment.value.isImmersiveMedia = true
        let coordinator = make(environment: environment, settings: settings)
        coordinator.start()
        defer { coordinator.stop() }
        let builtIn = coordinator.presentationModel
        let external = try XCTUnwrap(coordinator.presentationModel(for: .init(rawValue: 2)))
        builtIn.notificationCoordinator.present(.charging(level: 80))
        XCTAssertEqual(builtIn.activityCoordinator.presentationContext, .normal)
        XCTAssertEqual(external.activityCoordinator.presentationContext, .immersiveMedia)
        XCTAssertNotNil(builtIn.notificationCoordinator.active)
        XCTAssertNil(external.notificationCoordinator.active)
        XCTAssertEqual(builtIn.activityCoordinator.liveActivities.map(\.id), external.activityCoordinator.liveActivities.map(\.id))
    }

    func testSettingsApplyImmediatelyAndKeepSavedMonitorAcrossDisconnectAndChangedID() async throws {
        let source = MultipleDisplaySource()
        let uuid = UUID()
        let external = NotchiumDisplaySnapshot(id: .init(rawValue: 2), name: "Studio monitor",
            frame: source.displays[0].frame, isBuiltIn: false, isPrimary: true, persistentID: uuid)
        source.displays[0] = external
        let settings = NotchDisplaySettings()
        let coordinator = make(source: source, settings: settings)
        coordinator.start()
        defer { coordinator.stop() }
        settings.preferences.selection = .selected
        settings.preferences.selectedDisplayKey = external.selectionKey
        await waitUntil { coordinator.shellPlacement?.display.id == external.id }
        XCTAssertEqual(coordinator.shellPlacement?.display.id, external.id)
        source.displays = [builtInDisplay()]
        coordinator.refreshDisplayConfiguration()
        XCTAssertEqual(coordinator.shellPlacement?.display.id.rawValue, 1)
        XCTAssertEqual(settings.preferences.selectedDisplayKey, external.selectionKey)
        let reconnected = NotchiumDisplaySnapshot(id: .init(rawValue: 8), name: external.name,
            frame: external.frame, isBuiltIn: false, isPrimary: true, persistentID: uuid)
        source.displays.append(reconnected)
        coordinator.refreshDisplayConfiguration()
        XCTAssertEqual(coordinator.shellPlacement?.display.id, reconnected.id)
        XCTAssertNil(coordinator.presentationModel(for: .init(rawValue: 1)))
    }

    func testRemovingAdditionalDisplayCancelsItsInteractionWithoutClearingSharedMusic() async throws {
        let settings = NotchDisplaySettings()
        settings.preferences.selection = .all
        let source = MultipleDisplaySource()
        let coordinator = make(source: source, settings: settings)
        coordinator.start()
        defer { coordinator.stop() }
        let external = try XCTUnwrap(coordinator.presentationModel(for: .init(rawValue: 2)))
        external.present(.expanded, animated: false)
        let music = NotchActivity(id: UUID(), kind: .media, title: "Playing", subtitle: nil, duration: nil)
        external.activityCoordinator.present(music)
        source.displays.removeAll { !$0.isBuiltIn }
        coordinator.refreshDisplayConfiguration()
        XCTAssertEqual(external.visualState, .collapsed)
        XCTAssertNil(coordinator.presentationModel(for: .init(rawValue: 2)))
        XCTAssertTrue(coordinator.presentationModel.activityCoordinator.contains(id: music.id))
        settings.preferences.selection = .builtIn
        await drainMainActorTasks()
        XCTAssertTrue(coordinator.presentationModel.activityCoordinator.contains(id: music.id))
    }

    func testKeyboardOpenTargetsPointerDisplayAndSleepWakeCollapsesEachSession() throws {
        let settings = NotchDisplaySettings()
        settings.preferences.selection = .all
        let environment = MultipleDisplayEnvironment()
        environment.value.pointerLocation = CGPoint(x: -1000, y: 500)
        var panels: [MultipleDisplayPanel] = []
        let coordinator = make(environment: environment, settings: settings, panels: { panels.append($0) })
        coordinator.start()
        defer { coordinator.stop() }
        let external = try XCTUnwrap(coordinator.presentationModel(for: .init(rawValue: 2)))
        coordinator.openForKeyboard()
        XCTAssertEqual(external.visualState, .expanded)
        XCTAssertEqual(coordinator.presentationModel.visualState, .collapsed)
        XCTAssertEqual(panels[1].focuses, 1)
        coordinator.presentationModel.present(.expanded, animated: false)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertTrue(panels.allSatisfy { $0.placement == nil })
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertEqual(external.visualState, .collapsed)
        XCTAssertEqual(coordinator.presentationModel.visualState, .collapsed)
        XCTAssertEqual(coordinator.shellPlacements.count, 2)
    }

    func testDisplayPreferencesPersistAndCorruptDataUsesBuiltInDefault() throws {
        let suite = "NotchDisplayTests.\(UUID())"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        let settings = NotchDisplaySettings(storage: storage)
        XCTAssertEqual(settings.preferences.selection, .builtIn)
        settings.preferences.selection = .selected
        settings.preferences.selectedDisplayKey = "uuid:fixture"
        settings.preferences.selectedDisplayName = "Studio"
        settings.preferences.createsNotch = true
        XCTAssertEqual(NotchDisplaySettings(storage: storage).preferences, settings.preferences)
        for key in storage.dictionaryRepresentation().keys where key.hasPrefix("notchium.display.") {
            storage.set(Data("invalid".utf8), forKey: key)
        }
        XCTAssertEqual(NotchDisplaySettings(storage: storage).preferences, NotchDisplayPreferences())
    }

    private func make(clock: any AppClock = TestAppClock(now: Date(), automaticallyAdvances: false),
                      source: MultipleDisplaySource = MultipleDisplaySource(),
                      environment: MultipleDisplayEnvironment = MultipleDisplayEnvironment(),
                      settings: NotchDisplaySettings = NotchDisplaySettings(),
                      panels: @escaping (MultipleDisplayPanel) -> Void = { _ in }) -> NotchiumDisplayCoordinator {
        NotchiumDisplayCoordinator(clock: clock, displaySource: source, environmentSource: environment,
            panelControllerFactory: { _ in
                let panel = MultipleDisplayPanel()
                panels(panel)
                return panel
            }, settings: settings)
    }
}

final class SimulatedNotchGeometryTests: XCTestCase {
    func testSimulatedNotchUsesPhysicalNotchToDisplayRatiosAndGlobalTopAnchor() throws {
        let builtIn = builtInDisplay()
        let external = externalDisplay(frame: CGRect(x: -1920, y: 400, width: 1920, height: 1080))
        var preferences = NotchDisplayPreferences()
        preferences.selection = .all
        preferences.createsNotch = true
        let placements = NotchDisplayPlacementPolicy.placements(displays: [external, builtIn], preferences: preferences)
        XCTAssertEqual(placements[0].mode, .physicalNotch)
        let placement = try XCTUnwrap(placements.last)
        XCTAssertEqual(placement.mode, .simulatedNotch)
        let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)
        XCTAssertNil(layout.hardwareNotchGeometry, "A simulated notch must draw black rather than exclude hardware pixels")
        XCTAssertEqual(layout.collapsedVisibleFrame.width / external.frame.width, 212 / 1512, accuracy: 0.0001)
        XCTAssertEqual(layout.collapsedVisibleFrame.height / external.frame.height, 38 / 982, accuracy: 0.0001)
        XCTAssertEqual(layout.collapsedVisibleFrame.midX, external.frame.midX, accuracy: 0.001)
        XCTAssertEqual(layout.collapsedVisibleFrame.maxY, external.frame.maxY)
        XCTAssertEqual(layout.bottomCornerRadius, 8)
        XCTAssertEqual(NotchGeometryResolver.layout(for: placement, state: .expanded).collapsedBottomCornerRadius, 8)
        XCTAssertEqual(NotchGeometryResolver.layout(for: placement, state: .expanded).expandedSize, ExpandedNotchLayout.size)
    }

    func testSimulationWorksWithoutNotchedHardwareAndTracksDisplayResolution() throws {
        var preferences = NotchDisplayPreferences()
        preferences.createsNotch = true
        let external = externalDisplay(frame: CGRect(x: 500, y: -1000, width: 1512, height: 982))
        let placement = try XCTUnwrap(NotchDisplayPlacementPolicy.placements(displays: [external], preferences: preferences).first)
        let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)
        XCTAssertEqual(layout.surfaceSize, CGSize(width: 212, height: 38))
        XCTAssertEqual(layout.collapsedVisibleFrame.maxY, external.frame.maxY)
    }
}
