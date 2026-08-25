import AppKit
import SwiftUI

@MainActor
final class NotchiumPanelController {
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
        panel.contentView = NSHostingView(rootView: NotchiumShellView(model: model))
        panel.setAccessibilityLabel("Notchium productivity panel")
    }

    func show(on screen: NSScreen, geometry: NotchiumScreenGeometry) {
        panel.setFrame(geometry.panelFrame, display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        model.collapse()
        panel.orderOut(nil)
    }
}
