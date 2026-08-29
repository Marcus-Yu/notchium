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

private final class NotchTrackingHostingView: NSHostingView<NotchiumShellView> {
    var hoverHandler: ((Bool) -> Void)?
    private var shellTrackingArea: NSTrackingArea?

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override func updateTrackingAreas() {
        if let shellTrackingArea {
            removeTrackingArea(shellTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        shellTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hoverHandler?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hoverHandler?(false)
    }
}

@MainActor
final class NotchiumPanelController: NSObject, NotchPanelControlling, NSWindowDelegate {
    private let panel: NotchiumPanel
    private let model: DynamicIslandPresentationModel
    private var hostingView: NotchTrackingHostingView?
    private var currentFrame: CGRect?
    private var escapeMonitor: Any?

    init(model: DynamicIslandPresentationModel) {
        self.model = model
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
            placement: placement,
            layout: layout,
            renderConfiguration: renderConfiguration
        )

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = NotchTrackingHostingView(rootView: rootView)
            hostingView.hoverHandler = { [weak model] isHovered in
                model?.setHovered(isHovered)
            }
            hostingView.setAccessibilityIdentifier("notchium.shell.host")
            panel.contentView = hostingView
            self.hostingView = hostingView
        }

        updateFrame(layout.panelFrame, animated: animated)
        let showsExpandedShadow = model.visualState == .expanded
        if panel.hasShadow != showsExpandedShadow {
            panel.hasShadow = showsExpandedShadow
            panel.invalidateShadow()
        }

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
        currentFrame = nil
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

    private func updateFrame(_ frame: CGRect, animated: Bool) {
        guard currentFrame != frame else { return }
        let previousFrame = currentFrame
        currentFrame = frame

        guard animated, previousFrame != nil else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = model.reduceMotion
                ? 0.12
                : model.visualState == .expanded ? 0.30 : 0.18
            context.allowsImplicitAnimation = true
            context.timingFunction = model.reduceMotion
                ? CAMediaTimingFunction(name: .easeInEaseOut)
                : model.visualState == .expanded
                    ? CAMediaTimingFunction(controlPoints: 0.22, 0.92, 0.26, 1.06)
                    : CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
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
