import AppKit

@MainActor
public final class NotchiumPanelCoordinator: NSObject {
    public let presentationModel: DynamicIslandPresentationModel
    public private(set) var hasBuiltInNotch = false

    private let panelController: NotchiumPanelController
    private var isStarted = false

    public override init() {
        let presentationModel = DynamicIslandPresentationModel()
        self.presentationModel = presentationModel
        panelController = NotchiumPanelController(model: presentationModel)
        super.init()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        refreshPanelPlacement()
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        panelController.close()
    }

    @objc
    private func screenConfigurationChanged() {
        refreshPanelPlacement()
    }

    @objc
    private func workspaceDidWake() {
        refreshPanelPlacement()
    }

    private func refreshPanelPlacement() {
        guard let placement = NotchiumScreenGeometry.builtInNotchedScreen() else {
            hasBuiltInNotch = false
            panelController.close()
            return
        }

        hasBuiltInNotch = true
        panelController.show(on: placement.screen, geometry: placement.geometry)
    }
}
