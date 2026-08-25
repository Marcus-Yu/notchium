import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    private let panel: NSPanel
    private let model: DynamicIslandPresentationModel

    init(model: DynamicIslandPresentationModel) {
        self.model = model
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: NotchShellView(model: model))
        panel.setAccessibilityLabel("Notch productivity panel")
    }

    func show(on screen: NSScreen, geometry: NotchScreenGeometry) {
        panel.setFrame(geometry.panelFrame, display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        model.collapse()
        panel.orderOut(nil)
    }
}
