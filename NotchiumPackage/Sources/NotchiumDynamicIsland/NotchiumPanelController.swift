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
    func orderFrontRegardless()
    func hide()
}

private final class NotchHostingView: NSHostingView<NotchiumShellView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

@MainActor
final class NotchiumPanelController: NSObject, NotchPanelControlling, NSWindowDelegate {
    private let panel: NotchPanel
    private let model: DynamicIslandPresentationModel
    private let allowsPointerDrivenHover: Bool
    private var hostingView: NotchHostingView?
    private var currentLayout: NotchPanelLayout?
    private var escapeMonitor: Any?
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var positionedDisplayID: CGDirectDisplayID?
    private var positionedScreenFrame: NSRect?

    init(model: DynamicIslandPresentationModel) {
        self.model = model
#if DEBUG
        allowsPointerDrivenHover = !ProcessInfo.processInfo.arguments.contains("--ui-testing")
#else
        allowsPointerDrivenHover = true
#endif
        let panel = NotchPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 640,
                height: 210
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.applyNotchWindowBehavior()

#if DEBUG
        assert(panel.collectionBehavior.contains(.canJoinAllSpaces))
        assert(panel.collectionBehavior.contains(.stationary))
        assert(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        assert(panel.collectionBehavior.contains(.ignoresCycle))

        print("""
        [Notchium Window Behavior]
        canJoinAllSpaces:
        \(panel.collectionBehavior.contains(.canJoinAllSpaces))

        stationary:
        \(panel.collectionBehavior.contains(.stationary))

        fullScreenAuxiliary:
        \(panel.collectionBehavior.contains(.fullScreenAuxiliary))

        ignoresCycle:
        \(panel.collectionBehavior.contains(.ignoresCycle))

        frame:
        \(panel.frame)
        """)
#endif

        self.panel = panel
        super.init()

        panel.delegate = self
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
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
            updateRootView(rootView, in: hostingView, animated: animated)
            configureHostingView(hostingView, for: layout)
        } else {
            let hostingView = NotchHostingView(rootView: rootView)
            hostingView.setAccessibilityIdentifier("notchium.shell.host")
            configureHostingView(hostingView, for: layout)
            panel.contentView = hostingView
            self.hostingView = hostingView
        }

        currentLayout = layout
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = model.visualState == .collapsed
        installPointerMonitorsIfNeeded()

        if model.visualState == .expanded {
            installEscapeMonitorIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            removeEscapeMonitor()
            if panel.isKeyWindow {
                panel.resignKey()
            }
        }

        guard let screen = selectedScreen(for: placement) else {
            panel.orderOut(nil)
            return
        }
        if positionedDisplayID != screen.notchiumDisplayID
            || positionedScreenFrame != screen.frame {
            positionPanel(panel, on: screen)
            positionedDisplayID = screen.notchiumDisplayID
            positionedScreenFrame = screen.frame
        }
        panel.orderFrontRegardless()
        print("""
        [Notchium Actual Panel]
        screen.frame: \(screen.frame)
        screen.maxY: \(screen.frame.maxY)
        panel.frame: \(panel.frame)
        panel.maxY: \(panel.frame.maxY)
        panel.level: \(panel.level.rawValue)
        """)
    }

    private func updateRootView(
        _ rootView: NotchiumShellView,
        in hostingView: NotchHostingView,
        animated: Bool
    ) {
        guard animated else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hostingView.rootView = rootView
            }
            return
        }

        withAnimation(model.reduceMotion ? NotchMotion.reduced : NotchMotion.morph) {
            hostingView.rootView = rootView
        }
    }

    func orderFrontRegardless() {
        panel.orderFrontRegardless()
    }

    func hide() {
        removeEscapeMonitor()
        removePointerMonitors()
        currentLayout = nil
        positionedDisplayID = nil
        positionedScreenFrame = nil
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

    @MainActor
    func positionPanel(
        _ panel: NSPanel,
        on screen: NSScreen
    ) {
        let screenFrame = screen.frame

        let origin = NSPoint(
            x:
                screenFrame.midX
                - panel.frame.width / 2,
            y:
                screenFrame.maxY
                - panel.frame.height
        )

        panel.setFrameOrigin(origin)
    }

    private func selectedScreen(for placement: NotchShellPlacement) -> NSScreen? {
        NSScreen.screens.first {
            $0.notchiumDisplayID == placement.display.id.rawValue
        } ?? NSScreen.screens.first {
            $0.frame == placement.display.frame
        }
    }

    private func installPointerMonitorsIfNeeded() {
        let eventMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown]

        if globalPointerMonitor == nil {
            globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) {
                [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handlePointerEvent(event.type, at: NSEvent.mouseLocation)
                }
            }
        }

        if localPointerMonitor == nil {
            localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) {
                [weak self] event in
                let location = NSEvent.mouseLocation
                Task { @MainActor [weak self] in
                    self?.handlePointerEvent(event.type, at: location)
                }
                return event
            }
        }
    }

    private func handlePointerEvent(_ type: NSEvent.EventType, at point: CGPoint) {
        switch type {
        case .mouseMoved:
            if allowsPointerDrivenHover { handleMouseMoved(at: point) }
        case .leftMouseDown:
            handleClick(at: point)
        default:
            break
        }
    }

    func handleClick(at point: CGPoint) {
        guard let currentLayout else { return }
        let region = model.visualState == .collapsed
            ? currentLayout.collapsedHoverFrame : currentLayout.visibleSurfaceFrame
        if NotchHoverRegion.contains(point, in: region) {
            model.toggleExpanded()
        } else if model.visualState == .expanded {
            model.collapse()
        }
    }

    private func handleMouseMoved(at point: CGPoint) {
        guard let currentLayout else { return }
        let zone = model.visualState == .collapsed
            ? currentLayout.collapsedHoverFrame
            : currentLayout.visibleSurfaceFrame
        model.setHovered(NotchHoverRegion.contains(point, in: zone))
    }

    private func removePointerMonitors() {
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
            self.globalPointerMonitor = nil
        }
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
            self.localPointerMonitor = nil
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
