import AppKit
import NotchiumDynamicIsland
import SwiftUI

/// Shelf consumption rule: an item leaves the Shelf only when an external destination
/// actually accepted the drop. Cancelled/failed drags (no operation) keep it; the file itself
/// is never moved or deleted (the source only offers copy).
enum ShelfDragOutcome {
    static func consumesItem(_ operation: NSDragOperation) -> Bool { !operation.isEmpty }
}

/// A click-transparent AppKit drag source over a SwiftUI tile. Clicks, double-clicks and the
/// context menu still reach the tile; once the pointer moves past a small threshold a real
/// `NSDraggingSession` starts, whose end callback is the only reliable success signal.
struct ShelfDragSource: NSViewRepresentable {
    let url: URL
    let isEnabled: Bool
    /// Called only after a successful external drop.
    var onDelivered: (() -> Void)?
    @Environment(\.notchAuxiliaryInteraction) private var auxiliary

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.url = url
        view.isEnabled = isEnabled
        view.onDelivered = onDelivered
        view.auxiliary = auxiliary
    }

    static func dismantleNSView(_ view: DragSourceView, coordinator: ()) { view.stopMonitoring() }

    final class DragSourceView: NSView, NSDraggingSource {
        var url: URL?
        var isEnabled = true
        var onDelivered: (() -> Void)?
        var auxiliary = NotchAuxiliaryInteractionHandler()
        private var monitor: Any?
        private var mouseDown: NSEvent?
        private var isDragging = false
        private static let threshold: CGFloat = 4

        /// Never the click target: SwiftUI keeps selection, double-click and context menus.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? stopMonitoring() : startMonitoring()
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            mouseDown = nil
        }

        private func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
                [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        }

        private func handle(_ event: NSEvent) {
            guard event.window === window else { return }
            switch event.type {
            case .leftMouseDown:
                let point = convert(event.locationInWindow, from: nil)
                mouseDown = isEnabled && !isDragging && bounds.contains(point) && !isHiddenOrHasHiddenAncestor
                    ? event : nil
            case .leftMouseDragged:
                guard let down = mouseDown, !isDragging, let url else { return }
                let dx = event.locationInWindow.x - down.locationInWindow.x
                let dy = event.locationInWindow.y - down.locationInWindow.y
                guard hypot(dx, dy) > Self.threshold else { return }
                mouseDown = nil
                beginDrag(url: url, event: event)
            default:
                mouseDown = nil
            }
        }

        private func beginDrag(url: URL, event: NSEvent) {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let size = min(bounds.width, bounds.height, 48)
            item.setDraggingFrame(NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2,
                                         width: size, height: size), contents: icon)
            isDragging = true
            // The notch stays open while the item is in flight, as for other nested interactions.
            auxiliary.begin()
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Copy only. Offering .link lets Finder resolve the drop as an alias; offering .move
            // would relocate the original. A plain copy is what a Shelf hand-off means.
            context == .outsideApplication ? .copy : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                             operation: NSDragOperation) {
            isDragging = false
            auxiliary.end(actionSelected: false)
            if ShelfDragOutcome.consumesItem(operation) { onDelivered?() }
        }
    }
}
