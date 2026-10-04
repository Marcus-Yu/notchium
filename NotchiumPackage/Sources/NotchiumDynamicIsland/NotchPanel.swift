import AppKit

/// The window-level file drop target. A window is a stable AppKit dragging destination; a
/// SwiftUI drop modifier registers on the hosting view lazily and can be torn down mid-drag.
@MainActor protocol NotchFileDropHandling: AnyObject {
    func fileDragOperation(for info: NSDraggingInfo) -> NSDragOperation
    func fileDragExited()
    func performFileDrop(_ info: NSDraggingInfo) -> Bool
}

enum NotchFileDrop {
    /// File URLs as Finder puts them on the drag pasteboard: references, never copies.
    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self],
                                options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}

final class NotchPanel: NSPanel, NSDraggingDestination {
    weak var fileDropHandler: (any NotchFileDropHandling)?

    /// Above the menu bar and full-screen content at rest.
    static let restingLevel: NSWindow.Level = .screenSaver
    /// The window server never routes a drag to a window above its drag layer (verified with a
    /// real NSDraggingSession: a `.screenSaver` window receives nothing, `.popUpMenu` receives
    /// entered/prepare/perform). While a file drag is in progress the panel sits just below that
    /// layer, still above the menu bar, so Finder's drop can actually reach it.
    static let fileDragLevel: NSWindow.Level = .popUpMenu
    private var acceptsFileDrags = false
    private var nativeShareSources: Set<String> = []
    private var presentationContext: NotchPresentationContext = .normal

    func setPresentationContext(_ context: NotchPresentationContext) {
        presentationContext = context
        // Fullscreen changes rederive the CURRENT owners. They never save/restore a level.
        updateLevel()
        if context == .sleeping { orderOut(nil) }
    }

    func setAcceptsFileDrags(_ accepts: Bool) {
        acceptsFileDrags = accepts
        updateLevel()
    }

    func setNativeSharingPresented(_ presented: Bool, source: String) {
        if presented { nativeShareSources.insert(source) } else { nativeShareSources.remove(source) }
        updateLevel()
    }

    private func updateLevel() {
        // Native service windows and the picker sit above their floating source window.
        // Independent level owners restore the current drag state, never a stale saved level.
        let target: NSWindow.Level = !nativeShareSources.isEmpty ? .floating
            : (acceptsFileDrags ? Self.fileDragLevel : Self.restingLevel)
        if level != target { level = target }
    }

    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileDropHandler?.fileDragOperation(for: sender) ?? []
    }

    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileDropHandler?.fileDragOperation(for: sender) ?? []
    }

    func draggingExited(_ sender: (any NSDraggingInfo)?) {
        fileDropHandler?.fileDragExited()
    }

    func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        fileDropHandler?.fileDragOperation(for: sender).isEmpty == false
    }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        fileDropHandler?.performFileDrop(sender) ?? false
    }

    override func constrainFrameRect(
        _ frameRect: NSRect,
        to screen: NSScreen?
    ) -> NSRect {
        // Notchium intentionally occupies the menu-bar/notch region.
        // Do not let AppKit push the panel below the menu bar.
        frameRect
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func applyNotchWindowBehavior() {
        styleMask = [
            .borderless,
            .nonactivatingPanel,
        ]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        isMovable = false
        isMovableByWindowBackground = false

        hidesOnDeactivate = false
        canHide = false
        isReleasedWhenClosed = false

        animationBehavior = .none

        updateLevel()

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
    }
}
