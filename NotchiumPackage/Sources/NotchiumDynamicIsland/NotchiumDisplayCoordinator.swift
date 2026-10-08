import AppKit
import Combine
import NotchiumCore
import Observation

@MainActor
@Observable
public final class NotchiumDisplayCoordinator: NSObject {
    public let presentationModel: DynamicIslandPresentationModel
    public private(set) var displayState = DisplayPresentationState()
    public private(set) var shellPlacement: NotchShellPlacement?

    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private let environmentSource: any DisplayEnvironmentReading
    @ObservationIgnored private var evidence = DisplayInteractionEvidence()
    @ObservationIgnored private var reconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var needsTopologyRebuild = false
    @ObservationIgnored private var needsSpaceReassertion = false
    @ObservationIgnored private var lastSurfaceState: NotchStableState?
    @ObservationIgnored private var panelIsHidden = true
    @ObservationIgnored private var lastPanelLayout: NotchPanelLayout?
    @ObservationIgnored private var lastPanelPlacement: NotchShellPlacement?
    @ObservationIgnored private var lastRenderConfiguration: NotchShellRenderConfiguration?
    @ObservationIgnored private let displaySource: any NotchiumDisplaySnapshotting
    @ObservationIgnored private let panelController: any NotchPanelControlling
    @ObservationIgnored private var pageObservation: AnyCancellable?
    @ObservationIgnored private var isStarted = false
    private var isSleeping: Bool { displayState.sleeping }
    @ObservationIgnored private var lifecycleGeneration = 0
    @ObservationIgnored private var presentationObservationGeneration = 0
    @ObservationIgnored private var screenCorrectionGeneration = 0
#if DEBUG
    public let debugModel: NotchShellDebugModel
    @ObservationIgnored private var debugObservationGeneration = 0
#endif

#if DEBUG
    public init(
        clock: any AppClock,
        debugModel: NotchShellDebugModel
    ) {
        let presentationModel = DynamicIslandPresentationModel(clock: clock)
        self.presentationModel = presentationModel
        self.debugModel = debugModel
        self.clock = clock
        environmentSource = AppKitDisplayEnvironmentSource()
        displaySource = AppKitDisplaySource()
        panelController = NotchiumPanelController(model: presentationModel)
        super.init()
    }
#else
    public init(clock: any AppClock) {
        let presentationModel = DynamicIslandPresentationModel(clock: clock)
        self.presentationModel = presentationModel
        self.clock = clock
        environmentSource = AppKitDisplayEnvironmentSource()
        displaySource = AppKitDisplaySource()
        panelController = NotchiumPanelController(model: presentationModel)
        super.init()
    }
#endif

#if DEBUG
    init(
        clock: any AppClock,
        displaySource: any NotchiumDisplaySnapshotting,
        environmentSource: (any DisplayEnvironmentReading)? = nil,
        panelControllerFactory: @MainActor (DynamicIslandPresentationModel) -> any NotchPanelControlling,
        debugModel: NotchShellDebugModel = NotchShellDebugModel(arguments: [])
    ) {
        let presentationModel = DynamicIslandPresentationModel(clock: clock)
        self.presentationModel = presentationModel
        self.clock = clock
        self.environmentSource = environmentSource ?? EmptyDisplayEnvironmentSource()
        self.displaySource = displaySource
        panelController = panelControllerFactory(presentationModel)
        self.debugModel = debugModel
        super.init()
    }
#else
    init(
        clock: any AppClock,
        displaySource: any NotchiumDisplaySnapshotting,
        environmentSource: (any DisplayEnvironmentReading)? = nil,
        panelControllerFactory: @MainActor (DynamicIslandPresentationModel) -> any NotchPanelControlling
    ) {
        let presentationModel = DynamicIslandPresentationModel(clock: clock)
        self.presentationModel = presentationModel
        self.clock = clock
        self.environmentSource = environmentSource ?? EmptyDisplayEnvironmentSource()
        self.displaySource = displaySource
        panelController = panelControllerFactory(presentationModel)
        super.init()
    }
#endif

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        lifecycleGeneration &+= 1
        displayState.setSleeping(false, evidence: evidence)
        presentationModel.activityCoordinator.onSubmission = { [weak self] in
            self?.resolvePassiveOwnership()
        }
        let lifecycleGeneration = lifecycleGeneration
        environmentSource.start { [weak self] in
            guard let self, lifecycleGeneration == self.lifecycleGeneration else { return }
            self.scheduleReconciliation(topology: false)
        }
        panelController.setInteractionHandler { [weak self] point in
            guard let self, let display = self.displayState.availableDisplays.first(where: { $0.frame.contains(point) }) else { return }
            self.claimDisplay(display.id)
        }
        pageObservation = presentationModel.pageModel.$selectedPage.removeDuplicates().dropFirst().sink { [weak self] _ in
            // Published emits before assignment; reconcile after the selection has changed.
            Task { @MainActor [weak self] in
                guard let self, self.isStarted, !self.isSleeping,
                      lifecycleGeneration == self.lifecycleGeneration else { return }
                self.reconcilePanel(animated: true)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self, selector: #selector(workspaceScreensDidSleep),
                                    name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(frontmostApplicationChanged),
                                    name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceScreensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceScreensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        observePresentationChanges()
#if DEBUG
        observeDebugChanges()
        presentationModel.present(debugModel.presentation, animated: false)
#endif
        refreshDisplayConfiguration()
        if shellPlacement == nil { panelController.hide() }
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        lifecycleGeneration &+= 1
        pageObservation?.cancel(); pageObservation = nil
        environmentSource.stop()
        reconciliationTask?.cancel(); reconciliationTask = nil
        needsTopologyRebuild = false
        needsSpaceReassertion = false
        presentationModel.activityCoordinator.onSubmission = nil
        panelController.setInteractionHandler(nil)
        presentationObservationGeneration &+= 1
        screenCorrectionGeneration &+= 1
#if DEBUG
        debugObservationGeneration &+= 1
#endif
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        presentationModel.reset()
        panelController.hide()
        panelIsHidden = true
        shellPlacement = nil
        lastPanelLayout = nil
        lastPanelPlacement = nil
        lastRenderConfiguration = nil
        displayState = DisplayPresentationState()
    }

    isolated deinit {
        reconciliationTask?.cancel()
        environmentSource.stop()
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
        preserveOpenOwnership()
        evidence = environmentSource.evidence(displays: snapshots)
        displayState.rebuild(snapshots, evidence: evidence)
        applyDisplayState()
    }

    /// Explicit interaction owns one display until this open/auxiliary session ends.
    public func claimDisplay(_ id: NotchiumDisplayID) {
        guard isStarted, !isSleeping else { return }
        screenCorrectionGeneration &+= 1
        reconciliationTask?.cancel(); reconciliationTask = nil
        if needsTopologyRebuild {
            needsTopologyRebuild = false
            refreshDisplayConfiguration()
        }
        evidence = environmentSource.evidence(displays: displayState.availableDisplays)
        displayState.interact(on: id, evidence: evidence)
        applyDisplayState()
        if needsSpaceReassertion, shellPlacement != nil { panelController.orderFrontRegardless() }
        needsSpaceReassertion = false
    }

    /// An explicit menu command opens the existing owned panel for keyboard operation.
    public func openForKeyboard() {
        guard isStarted, !isSleeping else { return }
        presentationModel.present(.expanded, animated: false)
        preserveOpenOwnership()
        reconcilePanel(animated: false)
        panelController.focusExpandedPanel()
    }

    private func preserveOpenOwnership() {
        if presentationModel.visualState != .collapsed || presentationModel.isAuxiliaryInteractionPresented {
            if let id = displayState.ownedDisplayID { displayState.interact(on: id, evidence: evidence) }
        } else {
            displayState.releaseDirectOwnership()
        }
    }

    private func resolvePassiveOwnership() {
        guard isStarted, !isSleeping else { return }
        preserveOpenOwnership()
        // Playback starts and pauses inside a fullscreen Space without a Space, activation or
        // presentation-option change, so an activity arriving there re-reads current truth.
        if evidence.isFullscreen {
            evidence = environmentSource.evidence(displays: displayState.availableDisplays)
        } else {
            evidence.pointerLocation = environmentSource.pointerLocation
        }
        displayState.resolve(evidence)
        applyDisplayState()
    }

    private func applyDisplayState() {
        let placement = displayState.shellPlacement
#if DEBUG
        let selected = debugModel.override(placement: placement)
#else
        let selected = placement
#endif
        let moved = selected?.display.id != shellPlacement?.display.id || selected?.mode != shellPlacement?.mode
        shellPlacement = selected
        updatePresentationContext()
        // Migration retains the existing model, hosting view, page session and activity IDs.
        // The AppKit controller orders out/repositions/orders in without animating coordinates.
        reconcilePanel(animated: !moved)
    }

    private func updatePresentationContext() {
        let context = displayState.presentationContext
#if DEBUG
        if presentationModel.activityCoordinator.presentationContext != context {
            print("[Notchium Presentation] context=\(context) owner=\(String(describing: displayState.ownedDisplayID?.rawValue)) generation=\(displayState.topologyGeneration)")
        }
#endif
        presentationModel.activityCoordinator.setPresentationContext(context)
        panelController.setPresentationContext(context)
    }

    /// One cancellation-aware coalescer for topology, Space, activation and KVO events.
    func scheduleReconciliation(topology: Bool, reassertSpace: Bool = false) {
        guard isStarted, !isSleeping else { return }
        needsTopologyRebuild = needsTopologyRebuild || topology
        needsSpaceReassertion = needsSpaceReassertion || reassertSpace
        screenCorrectionGeneration &+= 1
        let generation = screenCorrectionGeneration
        reconciliationTask?.cancel()
        reconciliationTask = Task { [weak self, clock] in
            guard !Task.isCancelled else { return }
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
                self.preserveOpenOwnership()
                self.evidence = self.environmentSource.evidence(displays: self.displayState.availableDisplays)
                self.displayState.resolve(self.evidence)
                self.applyDisplayState()
            }
            if reassert, self.shellPlacement != nil { self.panelController.orderFrontRegardless() }
        }
    }

    @objc private func screenConfigurationChanged() { scheduleReconciliation(topology: true) }
    @objc private func frontmostApplicationChanged() { scheduleReconciliation(topology: false) }
    @objc private func workspaceDidWake() { workspaceScreensDidWake() }

    @objc private func workspaceScreensDidSleep() {
        guard isStarted else { return }
        screenCorrectionGeneration &+= 1
        reconciliationTask?.cancel(); reconciliationTask = nil
        needsTopologyRebuild = false
        needsSpaceReassertion = false
        displayState.setSleeping(true, evidence: evidence)
        updatePresentationContext()
        presentationModel.present(.collapsed, animated: false)
        panelController.hide()
        panelIsHidden = true
        lastPanelLayout = nil
        lastPanelPlacement = nil
        lastRenderConfiguration = nil
    }

    @objc private func workspaceScreensDidWake() {
        guard isStarted else { return }
        displayState.setSleeping(false, evidence: evidence)
        refreshDisplayConfiguration()
        // A single settling reconciliation catches delayed WindowServer wake geometry.
        scheduleReconciliation(topology: true)
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        guard isStarted, !isSleeping else { return }
        presentationModel.prepareForSystemTransition()
        scheduleReconciliation(topology: false, reassertSpace: true)
    }

    private func reconcilePanel(animated: Bool) {
        guard isStarted, !isSleeping else { return }
        guard let shellPlacement else {
            if !panelIsHidden { panelController.hide() }
            panelIsHidden = true
            lastPanelLayout = nil
            lastPanelPlacement = nil
            lastRenderConfiguration = nil
            return
        }

#if DEBUG
        let renderConfiguration = debugModel.renderConfiguration
#else
        let renderConfiguration = NotchShellRenderConfiguration.automatic
#endif
        let surfaceState = presentationModel.surfaceState
        guard shellPlacement != lastPanelPlacement || surfaceState != lastSurfaceState
                || renderConfiguration != lastRenderConfiguration || panelIsHidden else { return }
        let layout = NotchGeometryResolver.layout(for: shellPlacement, state: surfaceState)
#if DEBUG
        debugModel.updateRuntimeGeometry(placement: shellPlacement, layout: layout)
#endif
        lastSurfaceState = surfaceState
        guard layout != lastPanelLayout || shellPlacement != lastPanelPlacement
                || renderConfiguration != lastRenderConfiguration else { return }
#if DEBUG
        printGeometry(placement: shellPlacement, layout: layout)
#endif
        panelIsHidden = false
        lastPanelLayout = layout
        lastPanelPlacement = shellPlacement
        lastRenderConfiguration = renderConfiguration
        panelController.reconcile(
            placement: shellPlacement,
            layout: layout,
            renderConfiguration: renderConfiguration,
            animated: animated
        )
    }

#if DEBUG
    private func printGeometry(
        placement: NotchShellPlacement,
        layout: NotchPanelLayout
    ) {
        let display = placement.display
        print("""
        [Notchium Geometry]
        Screen frame: \(display.frame)
        Visible frame: \(display.visibleFrame)
        Safe top: \(display.safeAreaInsets.top)
        Aux left: \(String(describing: display.auxiliaryTopLeftArea))
        Aux right: \(String(describing: display.auxiliaryTopRightArea))
        Hardware notch: \(String(describing: layout.hardwareNotchGeometry?.frame))
        Collapsed: \(layout.collapsedVisibleFrame)
        Panel: \(layout.panelFrame)
        Has hardware notch: \(layout.hasHardwareNotch)
        """)
    }
#endif

    private func observePresentationChanges() {
        presentationObservationGeneration &+= 1
        let generation = presentationObservationGeneration
        withObservationTracking {
            _ = presentationModel.presentationState
            _ = presentationModel.phase
            _ = presentationModel.reduceMotion
            _ = presentationModel.isAuxiliaryInteractionPresented
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted,
                      generation == self.presentationObservationGeneration else { return }
                self.preserveOpenOwnership()
                self.reconcilePanel(animated: true)
                self.observePresentationChanges()
            }
        }
    }

#if DEBUG
    private func observeDebugChanges() {
        debugObservationGeneration &+= 1
        let generation = debugObservationGeneration
        withObservationTracking {
            _ = debugModel.revision
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted,
                      generation == self.debugObservationGeneration else { return }
                self.refreshDisplayConfiguration()
                self.presentationModel.present(self.debugModel.presentation, animated: false)
                self.reconcilePanel(animated: false)
                self.observeDebugChanges()
            }
        }
    }
#endif
}
