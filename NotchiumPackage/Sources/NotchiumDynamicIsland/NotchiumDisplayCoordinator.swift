import AppKit
import Combine
import NotchiumCore
import Observation

@MainActor
@Observable
public final class NotchiumDisplayCoordinator: NSObject {
    public let presentationModel: DynamicIslandPresentationModel
    public private(set) var shellPlacement: NotchShellPlacement?

    public var hasBuiltInNotch: Bool {
        shellPlacement?.mode == .physicalNotch
    }

    @ObservationIgnored private let displaySource: any NotchiumDisplaySnapshotting
    @ObservationIgnored private let panelController: any NotchPanelControlling
    @ObservationIgnored private var pageObservation: AnyCancellable?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isSleeping = false
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
        displaySource = AppKitDisplaySource()
        panelController = NotchiumPanelController(model: presentationModel)
        super.init()
    }
#else
    public init(clock: any AppClock) {
        let presentationModel = DynamicIslandPresentationModel(clock: clock)
        self.presentationModel = presentationModel
        displaySource = AppKitDisplaySource()
        panelController = NotchiumPanelController(model: presentationModel)
        super.init()
    }
#endif

#if DEBUG
    init(
        clock: any AppClock,
        displaySource: any NotchiumDisplaySnapshotting,
        panelControllerFactory: @MainActor (DynamicIslandPresentationModel) -> any NotchPanelControlling,
        debugModel: NotchShellDebugModel = NotchShellDebugModel(arguments: [])
    ) {
        let presentationModel = DynamicIslandPresentationModel(clock: clock)
        self.presentationModel = presentationModel
        self.displaySource = displaySource
        panelController = panelControllerFactory(presentationModel)
        self.debugModel = debugModel
        super.init()
    }
#else
    init(
        clock: any AppClock,
        displaySource: any NotchiumDisplaySnapshotting,
        panelControllerFactory: @MainActor (DynamicIslandPresentationModel) -> any NotchPanelControlling
    ) {
        let presentationModel = DynamicIslandPresentationModel(clock: clock)
        self.presentationModel = presentationModel
        self.displaySource = displaySource
        panelController = panelControllerFactory(presentationModel)
        super.init()
    }
#endif

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        pageObservation = presentationModel.pageModel.$selectedPage.removeDuplicates().dropFirst().sink { [weak self] _ in
            // Published emits before assignment; reconcile after the selection has changed.
            Task { @MainActor [weak self] in
                guard let self, self.isStarted, !self.isSleeping else { return }
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
        refreshDisplayConfiguration(collapseForMove: false)
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        presentationObservationGeneration &+= 1
        screenCorrectionGeneration &+= 1
#if DEBUG
        debugObservationGeneration &+= 1
#endif
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        presentationModel.reset()
        panelController.hide()
        shellPlacement = nil
    }

    func refreshDisplayConfiguration(collapseForMove: Bool = true) {
        guard isStarted, !isSleeping else { return }
        let liveSnapshots = displaySource.snapshots()
#if DEBUG
        let snapshots = debugModel.snapshots(live: liveSnapshots)
        let selected = debugModel.override(
            placement: NotchiumDisplaySelectionPolicy.select(from: snapshots)
        )
#else
        let selected = NotchiumDisplaySelectionPolicy.select(from: liveSnapshots)
#endif

        let moved = selected?.display.id != shellPlacement?.display.id
            || selected?.mode != shellPlacement?.mode
        if moved, collapseForMove {
            presentationModel.present(.collapsed, animated: false)
        }
        shellPlacement = selected
        reconcilePanel(animated: !moved)
    }

    @objc
    private func screenConfigurationChanged() {
        refreshDisplayConfiguration()
        screenCorrectionGeneration &+= 1
        let generation = screenCorrectionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self,
                  self.isStarted,
                  generation == self.screenCorrectionGeneration else { return }
            self.refreshDisplayConfiguration(collapseForMove: false)
        }
    }

    @objc
    private func workspaceDidWake() {
        isSleeping = false
        refreshDisplayConfiguration()
    }

    @objc
    private func workspaceScreensDidSleep() {
        isSleeping = true
        presentationModel.present(.collapsed, animated: false)
        panelController.hide()
    }

    @objc
    private func workspaceScreensDidWake() {
        isSleeping = false
        refreshDisplayConfiguration()
    }

    @objc
    private func activeSpaceDidChange(_ notification: Notification) {
        guard isStarted, !isSleeping, shellPlacement != nil else { return }
        // Also cancel a queued hover while still passive. collapse() uses the
        // normal setExpanded(false) animation and keeps hover entry edge-driven.
        presentationModel.collapse()
        panelController.orderFrontRegardless()
    }

    private func reconcilePanel(animated: Bool) {
        guard let shellPlacement else {
            panelController.hide()
            return
        }

        let layout = NotchGeometryResolver.layout(
            for: shellPlacement,
            state: presentationModel.surfaceState,
            expandedSize: presentationModel.pageModel.selectedPage == .music
                ? NotchGeometryResolver.expandedMediaSize : NotchGeometryResolver.expandedNotchSize
        )
#if DEBUG
        debugModel.updateRuntimeGeometry(placement: shellPlacement, layout: layout)
        printGeometry(placement: shellPlacement, layout: layout)
        let renderConfiguration = debugModel.renderConfiguration
#else
        let renderConfiguration = NotchShellRenderConfiguration.automatic
#endif
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
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted,
                      generation == self.presentationObservationGeneration else { return }
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
                self.refreshDisplayConfiguration(collapseForMove: false)
                self.presentationModel.present(self.debugModel.presentation, animated: false)
                self.reconcilePanel(animated: false)
                self.observeDebugChanges()
            }
        }
    }
#endif
}
