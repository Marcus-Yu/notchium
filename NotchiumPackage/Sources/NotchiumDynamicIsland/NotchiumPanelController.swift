import AppKit
import SwiftUI

@MainActor
protocol NotchPanelControlling: AnyObject {
    func reconcile(
        placement: NotchShellPlacement,
        layout: NotchPanelLayout,
        renderConfiguration: NotchShellRenderConfiguration,
        animated: Bool
    )
    func hide()
}

private final class NotchiumPanel: NSPanel {
    var escapeHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        escapeHandler?()
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        escapeHandler?()
    }
}

private final class NotchHostingView: NSHostingView<NotchiumShellView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

@MainActor
final class NotchiumPanelController: NSObject, NotchPanelControlling, NSWindowDelegate {
    private let panel: NotchiumPanel
    private let model: DynamicIslandPresentationModel
    private let allowsPointerDrivenHover: Bool
    private var hostingView: NotchHostingView?
    private var currentLayout: NotchPanelLayout?
    private var escapeMonitor: Any?
    private var globalMouseMonitor: Any?

    init(model: DynamicIslandPresentationModel) {
        self.model = model
#if DEBUG
        allowsPointerDrivenHover = !ProcessInfo.processInfo.arguments.contains("--ui-testing")
#else
        allowsPointerDrivenHover = true
#endif
        panel = NotchiumPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.delegate = self
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.escapeHandler = { [weak self] in
            self?.handleEscapeCommand()
        }
        panel.setAccessibilityLabel("Notchium shell")
        panel.setAccessibilityIdentifier("notchium.shell.panel")
    }

    func reconcile(
        placement: NotchShellPlacement,
        layout: NotchPanelLayout,
        renderConfiguration: NotchShellRenderConfiguration,
        animated: Bool
    ) {
        let rootView = NotchiumShellView(
            model: model,
            layout: layout,
            renderConfiguration: renderConfiguration
        )

        if let hostingView {
            hostingView.rootView = rootView
            configureHostingView(hostingView, for: layout)
        } else {
            let hostingView = NotchHostingView(rootView: rootView)
            hostingView.setAccessibilityIdentifier("notchium.shell.host")
            configureHostingView(hostingView, for: layout)
            panel.contentView = hostingView
            self.hostingView = hostingView
        }

        currentLayout = layout
        panel.setFrame(layout.panelFrame, display: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = model.visualState != .expanded
        installGlobalMouseMonitorIfNeeded()

        if model.visualState == .expanded {
            installEscapeMonitorIfNeeded()
            panel.becomesKeyOnlyIfNeeded = false
            NSApp.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            panel.makeKey()
            panel.makeFirstResponder(hostingView)
        } else {
            removeEscapeMonitor()
            panel.becomesKeyOnlyIfNeeded = true
            if panel.isKeyWindow {
                panel.resignKey()
            }
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        removeEscapeMonitor()
        removeGlobalMouseMonitor()
        currentLayout = nil
        panel.hasShadow = false
        panel.invalidateShadow()
        if panel.isKeyWindow {
            panel.resignKey()
        }
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard model.visualState == .expanded else { return }
        model.collapse()
    }

    func handleEscapeCommand() {
        guard model.visualState == .expanded else { return }
        model.collapse()
    }

    private func configureHostingView(
        _ hostingView: NotchHostingView,
        for layout: NotchPanelLayout
    ) {
        hostingView.frame = NSRect(origin: .zero, size: layout.panelFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
    }

    private func installGlobalMouseMonitorIfNeeded() {
        guard allowsPointerDrivenHover, globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMouseMoved(at: NSEvent.mouseLocation)
            }
        }
    }

    private func handleMouseMoved(at point: CGPoint) {
        guard let currentLayout else { return }
        let zone = model.visualState == .expanded
            ? currentLayout.panelFrame
            : currentLayout.collapsedHoverFrame
        model.setHovered(NotchHoverRegion.contains(point, in: zone))
    }

    private func removeGlobalMouseMonitor() {
        guard let globalMouseMonitor else { return }
        NSEvent.removeMonitor(globalMouseMonitor)
        self.globalMouseMonitor = nil
    }

    private func installEscapeMonitorIfNeeded() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard (event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}"),
                  let self,
                  self.model.visualState == .expanded else {
                return event
            }
            self.handleEscapeCommand()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        guard let escapeMonitor else { return }
        NSEvent.removeMonitor(escapeMonitor)
        self.escapeMonitor = nil
    }
}
