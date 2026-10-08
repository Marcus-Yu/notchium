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
    func setPresentationContext(_ context: NotchPresentationContext)
    func setInteractionHandler(_ handler: (@MainActor (CGPoint) -> Void)?)
    func focusExpandedPanel()
}

extension NotchPanelControlling {
    func setPresentationContext(_ context: NotchPresentationContext) {}
    func setInteractionHandler(_ handler: (@MainActor (CGPoint) -> Void)?) {}
    func focusExpandedPanel() {}
}

private final class NotchHostingView: NSHostingView<NotchiumShellView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

@MainActor
final class NotchiumPanelController: NSObject, NotchPanelControlling, NSWindowDelegate, NotchFileDropHandling {
    private let panel: NotchPanel
    private let model: DynamicIslandPresentationModel
    private let allowsPointerDrivenHover: Bool
    private var hostingView: NotchHostingView?
    private var currentLayout: NotchPanelLayout?
    private var escapeMonitor: Any?
    private var globalPointerMonitor: Any?
    /// File-drag tracking: the drag pasteboard changes when any drag session begins.
    private var dragPasteboardChangeCount = 0
    private var isFileDrag: Bool?
    private var fileDragEndTask: Task<Void, Never>?
    private var localPointerMonitor: Any?
    private var interactionHandler: (@MainActor (CGPoint) -> Void)?
    private var presentationContext: NotchPresentationContext = .normal
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
                width: NotchGeometryResolver.panelSize.width,
                height: NotchGeometryResolver.panelSize.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.applyNotchWindowBehavior()
        panel.registerForDraggedTypes([.fileURL])

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
        panel.fileDropHandler = self
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.setAccessibilityLabel("Notchium shell")
        panel.setAccessibilityIdentifier("notchium.shell.panel")
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded(_:)),
            name: NSMenu.didEndTrackingNotification, object: nil)
    }

    isolated deinit {
        hide()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func menuBegan(_ notification: Notification) {
        guard model.surfaceState != .collapsed, let menu = notification.object as? NSMenu else { return }
        model.setAuxiliaryInteractionPresented(true, source: "menu.\(ObjectIdentifier(menu))")
    }

    @objc private func menuEnded(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        model.setAuxiliaryInteractionPresented(false, source: "menu.\(ObjectIdentifier(menu))")
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
        updateHitTesting(at: NSEvent.mouseLocation)
        installPointerMonitorsIfNeeded()

        if model.visualState == .expanded {
            panel.allowsKeyboardFocus = true
            installEscapeMonitorIfNeeded()
        } else {
            panel.allowsKeyboardFocus = false
            removeEscapeMonitor()
            if panel.isKeyWindow {
                panel.resignKey()
            }
        }

        guard let screen = selectedScreen(for: placement) else {
            panel.orderOut(nil)
            return
        }
        if panel.frame != layout.panelFrame {
            // Keep one panel and one hosting view. Order out only for a display migration;
            // geometry adjustments on the same display are immediate and never slide.
            if positionedDisplayID != nil, positionedDisplayID != screen.notchiumDisplayID {
                panel.orderOut(nil)
            }
            panel.setFrame(layout.panelFrame, display: true, animate: false)
            positionedDisplayID = screen.notchiumDisplayID
            positionedScreenFrame = screen.frame
        }
        if presentationContext != .sleeping { panel.orderFrontRegardless() }
        #if DEBUG
        print("""
        [Notchium Actual Panel]
        screen.frame: \(screen.frame)
        screen.maxY: \(screen.frame.maxY)
        panel.frame: \(panel.frame)
        panel.maxY: \(panel.frame.maxY)
        panel.level: \(panel.level.rawValue)
        """)
        #endif
    }

    private func updateRootView(
        _ rootView: NotchiumShellView,
        in hostingView: NotchHostingView,
        animated: Bool
    ) {
        // The stable SwiftUI shell owns its geometry animation and completion.
        // Root updates must not animate the page layout or restart the spring.
        hostingView.rootView = rootView
    }

    func setInteractionHandler(_ handler: (@MainActor (CGPoint) -> Void)?) {
        interactionHandler = handler
    }

    func setPresentationContext(_ context: NotchPresentationContext) {
        presentationContext = context
        panel.setPresentationContext(context)
    }

    func orderFrontRegardless() {
        guard currentLayout != nil, presentationContext != .sleeping else { return }
        panel.orderFrontRegardless()
    }

    func focusExpandedPanel() {
        guard currentLayout != nil, model.visualState == .expanded,
              presentationContext != .sleeping else { return }
        panel.allowsKeyboardFocus = true
        panel.makeKeyAndOrderFront(nil)
        panel.selectNextKeyView(nil)
    }

    func hide() {
        panel.allowsKeyboardFocus = false
        fileDragEndTask?.cancel()
        fileDragEndTask = nil
        panel.setAcceptsFileDrags(false)
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
        guard model.visualState == .expanded,
              !model.isAuxiliaryInteractionPresented else { return }
        model.collapse()
    }

    func handleEscapeCommand() {
        guard model.visualState == .expanded else { return }
        model.handleEscape()
    }

    private func configureHostingView(
        _ hostingView: NotchHostingView,
        for layout: NotchPanelLayout
    ) {
        hostingView.frame = NSRect(origin: .zero, size: layout.panelFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
    }

    private func selectedScreen(for placement: NotchShellPlacement) -> NSScreen? {
        NSScreen.screens.first {
            $0.notchiumDisplayID == placement.display.id.rawValue
        }
    }

    private func installPointerMonitorsIfNeeded() {
        let eventMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]

        if globalPointerMonitor == nil {
            globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) {
                [weak self] event in
                MainActor.assumeIsolated {
                    self?.handlePointerEvent(event.type, at: NSEvent.mouseLocation)
                }
            }
        }

        if localPointerMonitor == nil {
            localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) {
                [weak self] event in
                let location = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
                // AppKit calls event monitors on the main thread. Process before the native
                // Cancel button releases its lease, rather than queueing that click afterward.
                MainActor.assumeIsolated {
                    self?.handlePointerEvent(event.type, at: location)
                }
                return event
            }
        }
    }

    private func handlePointerEvent(_ type: NSEvent.EventType, at point: CGPoint) {
        switch type {
        case .mouseMoved:
            updateHitTesting(at: point)
            if allowsPointerDrivenHover { handleMouseMoved(at: point) }
        case .leftMouseDown:
            beginPointerDrag()
            handleClick(at: point)
        case .leftMouseDragged:
            handleDrag(at: point)
        case .leftMouseUp:
            endPointerDrag()
        default:
            break
        }
    }

    // MARK: File drags toward the notch

    /// Screen point for a drag location reported in panel coordinates.
    func screenPoint(forWindowPoint point: CGPoint) -> CGPoint { panel.convertPoint(toScreen: point) }
    func windowPoint(forScreenPoint point: CGPoint) -> CGPoint { panel.convertPoint(fromScreen: point) }

    /// Accepts external file drags near the collapsed notch, or over the open Shelf page.
    /// Drags that started inside Notchium (a Shelf item) are never re-ingested.
    func fileDragOperation(for info: NSDraggingInfo) -> NSDragOperation {
        guard info.draggingSource == nil, let currentLayout,
              !NotchFileDrop.fileURLs(from: info.draggingPasteboard).isEmpty else { return [] }
        let point = screenPoint(forWindowPoint: info.draggingLocation)
        if model.visualState == .collapsed {
            let inside = NotchHoverRegion.contains(point, in: Self.fileDropZone(for: currentLayout))
            model.setFileDragNearby(inside)
            model.setFileDropTargeted(inside)
            return inside ? .copy : []
        }
        let overShelf = model.pageModel.selectedPage == .shelf
            && NotchHoverRegion.contains(point, in: currentLayout.visibleSurfaceFrame)
        return overShelf ? .copy : []
    }

    func fileDragExited() {
        model.setFileDropTargeted(false)
    }

    func performFileDrop(_ info: NSDraggingInfo) -> Bool {
        guard !fileDragOperation(for: info).isEmpty else { return false }
        return model.acceptDroppedFiles(NotchFileDrop.fileURLs(from: info.draggingPasteboard))
    }

    private func beginPointerDrag() {
        fileDragEndTask?.cancel()
        // A new press ends any previous drag (our own outbound drags never report mouse-up here).
        if isFileDrag == true { model.endFileDrag() }
        panel.setAcceptsFileDrags(false)
        dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        isFileDrag = nil
    }

    /// Cheap per event: one change-count read until a drag session is identified, then a
    /// rectangle test. Nothing runs while no mouse button is held.
    func handleDrag(at point: CGPoint) {
        guard let currentLayout else { return }
        if isFileDrag == nil {
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != dragPasteboardChangeCount else { return }
            isFileDrag = pasteboard.canReadObject(forClasses: [NSURL.self],
                                                  options: [.urlReadingFileURLsOnly: true])
            // Identified at the very start of the drag, long before the pointer reaches the notch.
            if isFileDrag == true { panel.setAcceptsFileDrags(true) }
        }
        guard isFileDrag == true, model.visualState == .collapsed else { return }
        model.setFileDragNearby(NotchHoverRegion.contains(point, in: Self.fileDropZone(for: currentLayout)))
        updateHitTesting(at: point)
    }

    private func endPointerDrag() {
        guard isFileDrag == true else { isFileDrag = nil; return }
        isFileDrag = nil
        // Let the drop callback finish before the affordance retracts.
        fileDragEndTask?.cancel()
        fileDragEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.panel.setAcceptsFileDrags(false)
            self.model.endFileDrag()
            self.updateHitTesting(at: NSEvent.mouseLocation)
        }
    }

    /// Generous but local: the notch plus room below and beside it. Not the whole menu bar.
    static func fileDropZone(for layout: NotchPanelLayout) -> CGRect {
        let frame = layout.collapsedVisibleFrame
        return CGRect(x: frame.minX - 90, y: frame.minY - 90, width: frame.width + 180, height: frame.height + 90)
    }

    func handleClick(at point: CGPoint) {
        guard let currentLayout else { return }
        guard !model.consumePointerClickForAuxiliaryInteraction() else { return }
        if !NotchHoverRegion.contains(point, in: currentLayout.collapsedHoverFrame),
           let frame = notificationFrame(for: currentLayout), frame.contains(point) {
            // Notification actions, including Join and dismissal, own their clicks.
            return
        }
        if indicatorFrames(for: currentLayout).contains(where: { $0.contains(point) }) {
            // The secondary chip's own button promotes it; it never toggles the shell.
            return
        }
        let region = model.surfaceState == .collapsed
            ? currentLayout.collapsedHoverFrame : currentLayout.visibleSurfaceFrame
        if NotchHoverRegion.contains(point, in: region) {
            interactionHandler?(point)
            // The header owns pin/unpin; content clicks belong to native controls.
            if model.surfaceState == .collapsed
                || NotchHoverRegion.contains(point, in: currentLayout.collapsedHoverFrame) {
                model.toggleExpanded()
            }
        } else if model.collapsesOnOutsideClick {
            model.collapse()
        }
    }

    func handleMouseMoved(at point: CGPoint) {
        guard let currentLayout else { return }
        let insideNotification = notificationFrame(for: currentLayout)
            .map { NotchHoverRegion.contains(point, in: $0) } == true
        model.notificationCoordinator.setHovered(insideNotification)
        let zone = model.surfaceState == .collapsed
            ? currentLayout.collapsedHoverFrame
            : currentLayout.visibleSurfaceFrame
        // Completion buttons remain reachable in the small banner. Only hovering the normal
        // notch activation area opens the full shell; the banner body owns its own interaction.
        let keepsCompletionCompact = model.presentedNotification?.presentationStyle == .pomodoroCompletion
        let inside = NotchHoverRegion.contains(point, in: zone) || (insideNotification && !keepsCompletionCompact)
        model.setHovered(inside)
    }

    private func notificationFrame(for layout: NotchPanelLayout) -> CGRect? {
        if model.expandedMinorActivity != nil { return NotchExpandedMinorGeometry.frame(layout: layout) }
        guard let notification = model.presentedNotification else { return nil }
        return NotchNotificationGeometry.interactionFrame(for: notification.presentationStyle, layout: layout,
                                                          expanded: model.surfaceState != .collapsed)
    }

    private func indicatorFrames(for layout: NotchPanelLayout) -> [CGRect] {
        model.presentedIndicators.map {
            NotchSecondaryGeometry.frame(layout: layout, beside: model.presentedNotification, kind: $0.kind)
        }
    }

    private func updateHitTesting(at point: CGPoint) {
        guard let currentLayout else { return }
        let inside = notificationFrame(for: currentLayout)
            .map { NotchHoverRegion.contains(point, in: $0) } == true
        model.notificationCoordinator.setHovered(inside)
        let insideSecondary = indicatorFrames(for: currentLayout).contains { NotchHoverRegion.contains(point, in: $0) }
        panel.ignoresMouseEvents = model.surfaceState == .collapsed && !inside && !insideSecondary
            && !model.showsFileDropTarget
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
                  event.window === self.panel,
                  !self.model.isAuxiliaryInteractionPresented,
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
