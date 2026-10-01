import AppKit
import NotchiumDynamicIsland
import SwiftUI

/// Shelf consumption rule: an item leaves the Shelf only when an external destination
/// actually accepted the drop. Cancelled/failed drags keep it. Filesystem operations are
/// performed by the destination, never by source-side deletion.
enum ShelfDragOutcome {
    static func consumesItem(_ operation: NSDragOperation) -> Bool {
        !operation.intersection([.copy, .move]).isEmpty
    }
}

/// A click-transparent AppKit drag source over a SwiftUI tile. Clicks, double-clicks and the
/// context menu still reach the tile; once the pointer moves past a small threshold a real
/// `NSDraggingSession` starts, whose end callback is the only reliable success signal.
struct ShelfDragSource: NSViewRepresentable {
    let url: URL
    let isEnabled: Bool
    var selectedURLs: [URL] = []
    /// Called only after a successful external drop.
    var onDelivered: (([URL]) -> Void)?
    @Environment(\.notchAuxiliaryInteraction) private var auxiliary

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.url = url
        view.selectedURLs = selectedURLs
        view.isEnabled = isEnabled
        view.onDelivered = onDelivered
        view.auxiliary = auxiliary
    }

    static func dismantleNSView(_ view: DragSourceView, coordinator: ()) { view.stopMonitoring() }

    final class DragSourceView: NSView, NSDraggingSource {
        var url: URL?
        var selectedURLs: [URL] = []
        var isEnabled = true
        var onDelivered: (([URL]) -> Void)?
        var auxiliary = NotchAuxiliaryInteractionHandler()
        private var monitor: Any?
        private var mouseDown: NSEvent?
        private var isDragging = false
        private var draggedURLs: [URL] = []
        private var scopedURLs: [URL] = []
        private var delivery: (([URL]) -> Void)?
        private let interactionSource = "shelf.drag.\(UUID())"
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
            draggedURLs = selectedURLs.contains(url) ? selectedURLs : [url]
            draggedURLs = draggedURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !draggedURLs.isEmpty else { return }
            scopedURLs = draggedURLs.filter { $0.startAccessingSecurityScopedResource() }
            delivery = onDelivered
            let size = min(bounds.width, bounds.height, 48)
            let items = draggedURLs.enumerated().map { index, file in
                let item = NSDraggingItem(pasteboardWriter: file as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: file.path)
                item.setDraggingFrame(NSRect(x: (bounds.width - size) / 2 + CGFloat(index) * 3,
                                             y: (bounds.height - size) / 2, width: size, height: size), contents: icon)
                return item
            }
            isDragging = true
            // The notch stays open while the item is in flight, as for other nested interactions.
            auxiliary.begin(source: interactionSource)
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            guard context == .outsideApplication else { return [] }
            // Finder owns the destination transaction, collision handling and cross-volume copy.
            // Never offer .link (aliases). Read-only sources can still be copied safely.
            return draggedURLs.allSatisfy { FileManager.default.isWritableFile(atPath: $0.path) }
                ? [.move, .copy] : .copy
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                             operation: NSDragOperation) {
            isDragging = false
            let deliveredURLs = draggedURLs
            scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            scopedURLs.removeAll()
            draggedURLs.removeAll()
            auxiliary.end(actionSelected: false, source: interactionSource)
            if ShelfDragOutcome.consumesItem(operation) { (delivery ?? onDelivered)?(deliveredURLs) }
            delivery = nil
        }
    }
}
