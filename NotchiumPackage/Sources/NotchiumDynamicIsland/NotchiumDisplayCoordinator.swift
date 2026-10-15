import AppKit
import NotchiumCore
import Observation

@MainActor
@Observable
public final class NotchiumDisplayCoordinator: NSObject {
    /// The first selected display's interaction model and the composition root's renderer bindings.
    public let presentationModel: DynamicIslandPresentationModel
    public let settings: NotchDisplaySettings
    public private(set) var displayState = DisplayPresentationState()
    public private(set) var shellPlacements: [NotchShellPlacement] = []
    public var shellPlacement: NotchShellPlacement? { shellPlacements.first }

    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private let activitySource: ActivityCoordinator
    @ObservationIgnored private let environmentSource: any DisplayEnvironmentReading
    @ObservationIgnored private let displaySource: any NotchiumDisplaySnapshotting
    @ObservationIgnored private let panelControllerFactory: @MainActor (DynamicIslandPresentationModel) -> any NotchPanelControlling
    @ObservationIgnored private let primarySession: NotchDisplaySession
    @ObservationIgnored private var additionalSessions: [NotchiumDisplayID: NotchDisplaySession] = [:]
    @ObservationIgnored private var lastInteractedDisplayID: NotchiumDisplayID?
    @ObservationIgnored private var evidence = DisplayInteractionEvidence()
    @ObservationIgnored private var reconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var needsTopologyRebuild = false
    @ObservationIgnored private var needsSpaceReassertion = false
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var lifecycleGeneration = 0
    @ObservationIgnored private var screenCorrectionGeneration = 0
    @ObservationIgnored private var settingsObservationGeneration = 0
    private var isSleeping: Bool { displayState.sleeping }
#if DEBUG
    public private(set) var debugModel = NotchShellDebugModel(arguments: [])
    @ObservationIgnored private var debugObservationGeneration = 0

    public convenience init(clock: any AppClock, debugModel: NotchShellDebugModel,
                            settings: NotchDisplaySettings = NotchDisplaySettings(storage: .standard)) {
        self.init(clock: clock, displaySource: AppKitDisplaySource(),
                  environmentSource: AppKitDisplayEnvironmentSource(),
                  panelControllerFactory: { NotchiumPanelController(model: $0) },
                  debugModel: debugModel, settings: settings)
    }
#else
    public convenience init(clock: any AppClock,
                            settings: NotchDisplaySettings = NotchDisplaySettings(storage: .standard)) {
        self.init(clock: clock, displaySource: AppKitDisplaySource(),
                  environmentSource: AppKitDisplayEnvironmentSource(),
                  panelControllerFactory: { NotchiumPanelController(model: $0) }, settings: settings)
    }
#endif

#if DEBUG
    convenience init(
        clock: any AppClock,
        displaySource: any NotchiumDisplaySnapshotting,
        environmentSource: (any DisplayEnvironmentReading)? = nil,
        panelControllerFactory: @escaping @MainActor (DynamicIslandPresentationModel) -> any NotchPanelControlling,
        debugModel: NotchShellDebugModel = NotchShellDebugModel(arguments: []),
        settings: NotchDisplaySettings = NotchDisplaySettings()
    ) {
        self.init(clock: clock, displaySource: displaySource, environmentSource: environmentSource,
                  panelControllerFactory: panelControllerFactory, displaySettings: settings)
        self.debugModel = debugModel
    }
#else
    convenience init(
        clock: any AppClock,
        displaySource: any NotchiumDisplaySnapshotting,
        environmentSource: (any DisplayEnvironmentReading)? = nil,
        panelControllerFactory: @escaping @MainActor (DynamicIslandPresentationModel) -> any NotchPanelControlling,
        settings: NotchDisplaySettings = NotchDisplaySettings()
    ) {
        self.init(clock: clock, displaySource: displaySource, environmentSource: environmentSource,
                  panelControllerFactory: panelControllerFactory, displaySettings: settings)
    }
#endif

    private init(
        clock: any AppClock,
        displaySource: any NotchiumDisplaySnapshotting,
        environmentSource: (any DisplayEnvironmentReading)?,
        panelControllerFactory: @escaping @MainActor (DynamicIslandPresentationModel) -> any NotchPanelControlling,
        displaySettings: NotchDisplaySettings
    ) {
        let activities = ActivityCoordinator(clock: clock)
        let presentationModel = DynamicIslandPresentationModel(
            clock: clock, activityCoordinator: ActivityCoordinator(projecting: activities))
        self.presentationModel = presentationModel
        activitySource = activities
        self.clock = clock
        self.settings = displaySettings
        self.environmentSource = environmentSource ?? EmptyDisplayEnvironmentSource()
        self.displaySource = displaySource
        self.panelControllerFactory = panelControllerFactory
        primarySession = NotchDisplaySession(model: presentationModel, panel: panelControllerFactory(presentationModel))
        super.init()
#if DEBUG
        primarySession.onLayout = { [weak self] placement, layout in
            self?.debugModel.updateRuntimeGeometry(placement: placement, layout: layout)
        }
#endif
    }

    /// Returns only an active display's model; feature providers are shared across these sessions.
    public func presentationModel(for displayID: NotchiumDisplayID) -> DynamicIslandPresentationModel? {
        session(for: displayID)?.model
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        lifecycleGeneration &+= 1
        displayState.preferences = settings.preferences
        displayState.setSleeping(false, evidence: evidence)
        activitySource.onSubmission = { [weak self] in self?.refreshPresentationEvidence() }
        let generation = lifecycleGeneration
        environmentSource.start { [weak self] in
            guard let self, generation == self.lifecycleGeneration else { return }
            self.scheduleReconciliation(topology: false)
        }
        configureInteraction(primarySession)
        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(workspaceScreensDidSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(frontmostApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(workspaceScreensDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(workspaceScreensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(workspaceScreensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(activeSpaceDidChange(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        observeSettingsChanges()
#if DEBUG
        observeDebugChanges()
        presentationModel.present(debugModel.presentation, animated: false)
#endif
        refreshDisplayConfiguration()
        if shellPlacement == nil { primarySession.panel.hide() }
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        lifecycleGeneration &+= 1
        screenCorrectionGeneration &+= 1
        settingsObservationGeneration &+= 1
#if DEBUG
        debugObservationGeneration &+= 1
#endif
        environmentSource.stop()
        reconciliationTask?.cancel(); reconciliationTask = nil
        needsTopologyRebuild = false
        needsSpaceReassertion = false
        activitySource.onSubmission = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        primarySession.stop()
        additionalSessions.values.forEach { $0.stop() }
        additionalSessions.removeAll()
        activitySource.clearAll()
        shellPlacements = []
        lastInteractedDisplayID = nil
        displayState = DisplayPresentationState()
    }

    isolated deinit {
        reconciliationTask?.cancel()
        environmentSource.stop()
        primarySession.stop()
        additionalSessions.values.forEach { $0.stop() }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func refreshDisplayConfiguration() {
        guard isStarted, !isSleeping else { return }
        let liveSnapshots = displaySource.snapshots()
#if DEBUG
        let snapshots = debugModel.snapshots(live: liveSnapshots)
#else
        let snapshots = liveSnapshots
#endif
        evidence = environmentSource.evidence(displays: snapshots)
        displayState.preferences = settings.preferences
        displayState.rebuild(snapshots, evidence: evidence)
        applyDisplayState()
    }

    /// Interaction chooses the keyboard destination without moving or expanding another panel.
    public func claimDisplay(_ id: NotchiumDisplayID) {
        guard isStarted, !isSleeping else { return }
        screenCorrectionGeneration &+= 1
        reconciliationTask?.cancel(); reconciliationTask = nil
        if needsTopologyRebuild {
            needsTopologyRebuild = false
            refreshDisplayConfiguration()
        }
        guard session(for: id) != nil else { return }
        lastInteractedDisplayID = id
        evidence = environmentSource.evidence(displays: displayState.availableDisplays)
        displayState.resolve(evidence)
        applyDisplayState()
        if needsSpaceReassertion { reassertPanels() }
        needsSpaceReassertion = false
    }

    public func openForKeyboard() {
        guard isStarted, !isSleeping else { return }
        let pointerDisplay = environmentSource.pointerLocation.flatMap { point in
            shellPlacements.first { $0.display.frame.contains(point) }?.display.id
        }
        guard let target = pointerDisplay.flatMap({ session(for: $0) })
            ?? lastInteractedDisplayID.flatMap({ session(for: $0) })
            ?? shellPlacement.flatMap({ session(for: $0.display.id) }) else { return }
        target.model.present(.expanded, animated: false)
        target.reconcile(animated: false)
        target.panel.focusExpandedPanel()
    }

    private var sessions: [NotchDisplaySession] { [primarySession] + Array(additionalSessions.values) }

    private func session(for id: NotchiumDisplayID) -> NotchDisplaySession? {
        if shellPlacement?.display.id == id { return primarySession }
        return additionalSessions[id]
    }

    private func configureInteraction(_ session: NotchDisplaySession) {
        session.panel.setInteractionHandler { [weak self, weak session] _ in
            guard let id = session?.placement?.display.id else { return }
            self?.claimDisplay(id)
        }
    }

    private func refreshPresentationEvidence() {
        guard isStarted, !isSleeping else { return }
        // Media can enter or leave immersive playback without a Space/activation change.
        if evidence.isFullscreen {
            evidence = environmentSource.evidence(displays: displayState.availableDisplays)
            displayState.resolve(evidence)
            applyDisplayState()
        }
    }

    private func applyDisplayState() {
        var placements = displayState.shellPlacements
#if DEBUG
        placements = placements.compactMap { debugModel.override(placement: $0) }
        let configuration = debugModel.renderConfiguration
#else
        let configuration = NotchShellRenderConfiguration.automatic
#endif
        shellPlacements = placements
        let additionalIDs = Set(placements.dropFirst().map { $0.display.id })
        for id in Array(additionalSessions.keys) where !additionalIDs.contains(id) {
            additionalSessions.removeValue(forKey: id)?.stop()
        }
        primarySession.update(placement: placements.first,
            context: displayState.presentationContext, configuration: configuration, animated: false)
        for placement in placements.dropFirst() {
            let session: NotchDisplaySession
            if let existing = additionalSessions[placement.display.id] {
                session = existing
            } else {
                let model = DynamicIslandPresentationModel(clock: clock,
                    activityCoordinator: ActivityCoordinator(projecting: activitySource))
                model.useRenderers(from: presentationModel)
                session = NotchDisplaySession(model: model, panel: panelControllerFactory(model))
                additionalSessions[placement.display.id] = session
                configureInteraction(session)
            }
            session.update(placement: placement,
                context: displayState.context(for: placement.display.id, evidence: evidence),
                configuration: configuration, animated: false)
        }
#if DEBUG
        if let placement = placements.first {
            debugModel.updateRuntimeGeometry(placement: placement,
                layout: NotchGeometryResolver.layout(for: placement, state: presentationModel.surfaceState))
        }
#endif
    }

    /// One coalescer for topology, Spaces, activation and presentation-option changes.
    func scheduleReconciliation(topology: Bool, reassertSpace: Bool = false) {
        guard isStarted, !isSleeping else { return }
        needsTopologyRebuild = needsTopologyRebuild || topology
        needsSpaceReassertion = needsSpaceReassertion || reassertSpace
        screenCorrectionGeneration &+= 1
        let generation = screenCorrectionGeneration
        reconciliationTask?.cancel()
        reconciliationTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: .milliseconds(80)) } catch { return }
            guard !Task.isCancelled, let self, self.isStarted, !self.isSleeping,
                  generation == self.screenCorrectionGeneration else { return }
            self.reconciliationTask = nil
            let rebuild = self.needsTopologyRebuild
            let reassert = self.needsSpaceReassertion
            self.needsTopologyRebuild = false
            self.needsSpaceReassertion = false
            if rebuild { self.refreshDisplayConfiguration() }
            else {
                self.evidence = self.environmentSource.evidence(displays: self.displayState.availableDisplays)
                self.displayState.resolve(self.evidence)
                self.applyDisplayState()
            }
            if reassert { self.reassertPanels() }
        }
    }

    private func reassertPanels() {
        for session in sessions where session.placement != nil { session.panel.orderFrontRegardless() }
    }

    @objc private func screenConfigurationChanged() { scheduleReconciliation(topology: true) }
    @objc private func frontmostApplicationChanged() { scheduleReconciliation(topology: false) }

    @objc private func workspaceScreensDidSleep() {
        guard isStarted else { return }
        screenCorrectionGeneration &+= 1
        reconciliationTask?.cancel(); reconciliationTask = nil
        needsTopologyRebuild = false
        needsSpaceReassertion = false
        displayState.setSleeping(true, evidence: evidence)
        sessions.forEach { $0.sleep() }
    }

    @objc private func workspaceScreensDidWake() {
        guard isStarted else { return }
        displayState.setSleeping(false, evidence: evidence)
        refreshDisplayConfiguration()
        scheduleReconciliation(topology: true)
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        guard isStarted, !isSleeping else { return }
        sessions.forEach { $0.model.prepareForSystemTransition() }
        scheduleReconciliation(topology: false, reassertSpace: true)
    }

    private func observeSettingsChanges() {
        settingsObservationGeneration &+= 1
        let generation = settingsObservationGeneration
        withObservationTracking { _ = settings.preferences } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted, generation == self.settingsObservationGeneration else { return }
                self.displayState.preferences = self.settings.preferences
                self.displayState.resolve(self.evidence)
                if !self.isSleeping { self.applyDisplayState() }
                self.observeSettingsChanges()
            }
        }
    }

#if DEBUG
    private func observeDebugChanges() {
        debugObservationGeneration &+= 1
        let generation = debugObservationGeneration
        withObservationTracking { _ = debugModel.revision } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted, generation == self.debugObservationGeneration else { return }
                self.refreshDisplayConfiguration()
                self.presentationModel.present(self.debugModel.presentation, animated: false)
                self.primarySession.reconcile(animated: false)
                self.observeDebugChanges()
            }
        }
    }
#endif
}
