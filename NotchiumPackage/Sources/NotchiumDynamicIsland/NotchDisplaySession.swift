import Observation

/// One native panel and interaction model per selected display. Activity data is projected
/// from the application source, while hover, pinning, navigation and auxiliary UI stay local.
@MainActor
final class NotchDisplaySession {
    let model: DynamicIslandPresentationModel
    let panel: any NotchPanelControlling
    var onLayout: ((NotchShellPlacement, NotchPanelLayout) -> Void)?
    private(set) var placement: NotchShellPlacement?
    private var lastLayout: NotchPanelLayout?
    private var lastPlacement: NotchShellPlacement?
    private var lastConfiguration: NotchShellRenderConfiguration?
    private var configuration = NotchShellRenderConfiguration.automatic
    private var observing = false
    private var observationGeneration = 0

    init(model: DynamicIslandPresentationModel, panel: any NotchPanelControlling) {
        self.model = model
        self.panel = panel
    }

    func update(placement: NotchShellPlacement?, context: NotchPresentationContext,
                configuration: NotchShellRenderConfiguration, animated: Bool,
                revalidatePanel: Bool = false) {
        if !observing {
            observing = true
            observePresentation()
        }
        if let previous = self.placement,
           previous.display.id != placement?.display.id
            || previous.display.persistentID != placement?.display.persistentID {
            // A different monitor never inherits an open interaction from this one.
            model.reset(clearingActivities: false)
        }
        self.placement = placement
        self.configuration = configuration
        let resuming = model.activityCoordinator.presentationContext == .sleeping && context != .sleeping
        model.activityCoordinator.setPresentationContext(context)
        if resuming { model.prepareForSystemWake() }
        panel.setPresentationContext(context)
        reconcile(animated: animated, force: revalidatePanel)
    }

    func reconcile(animated: Bool, force: Bool = false) {
        guard observing else { return }
        guard let placement, model.activityCoordinator.presentationContext != .sleeping else {
            hide()
            return
        }
        let layout = NotchGeometryResolver.layout(for: placement, state: model.surfaceState)
        guard force || layout != lastLayout || placement != lastPlacement || configuration != lastConfiguration else { return }
        lastLayout = layout
        lastPlacement = placement
        lastConfiguration = configuration
        panel.reconcile(placement: placement, layout: layout,
                        renderConfiguration: configuration, animated: animated)
        onLayout?(placement, layout)
    }

    func sleep() {
        model.prepareForSystemSleep()
        model.activityCoordinator.setPresentationContext(.sleeping)
        panel.setPresentationContext(.sleeping)
        hide()
    }

    func stop() {
        observing = false
        observationGeneration &+= 1
        panel.setInteractionHandler(nil)
        model.reset(clearingActivities: false)
        placement = nil
        hide()
    }

    private func hide() {
        if lastLayout != nil { panel.hide() }
        lastLayout = nil
        lastPlacement = nil
        lastConfiguration = nil
    }

    private func observePresentation() {
        observationGeneration &+= 1
        let generation = observationGeneration
        withObservationTracking {
            _ = model.presentationState
            _ = model.phase
            _ = model.reduceMotion
            _ = model.isAuxiliaryInteractionPresented
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observing, generation == self.observationGeneration else { return }
                self.reconcile(animated: true)
                self.observePresentation()
            }
        }
    }
}
