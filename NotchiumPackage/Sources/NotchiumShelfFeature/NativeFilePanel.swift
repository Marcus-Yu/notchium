import AppKit
import NotchiumDynamicIsland

/// Owns the panel until its native completion. No folder read or permission probe is
/// needed to present an open panel; selected URLs carry the user's access grant.
@MainActor
final class NativeFilePanel {
    private(set) var panel: NSOpenPanel?
    var makePanel: @MainActor () -> NSOpenPanel = { NSOpenPanel() }
    var present: @MainActor (NSOpenPanel) async -> NSApplication.ModalResponse = { panel in
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        return await panel.begin()
    }

    func choose(from window: NSWindow?, interaction: NotchAuxiliaryInteractionHandler) async -> [URL] {
        guard panel == nil else { return [] }
        let panel = makePanel()
        self.panel = panel
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Add to Shelf"
        panel.prompt = "Add"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        panel.level = .modalPanel
        // The source window identifies the clicked display, including independent shells.
        if let screen = window?.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2))
        }
        let source = "native.file-panel.\(UUID())"
        interaction.beginNativeSharing(in: window, source: source)
        defer {
            panel.orderOut(nil)
            self.panel = nil
            interaction.endNativeSharing(in: window, source: source, returnsToOpenSession: true)
            window?.orderFrontRegardless()
        }
        let response = await withTaskCancellationHandler {
            guard !Task.isCancelled else { return NSApplication.ModalResponse.cancel }
            return await present(panel)
        } onCancel: {
            Task { @MainActor [weak panel] in panel?.cancel(nil) }
        }
        return response == .OK && !Task.isCancelled ? panel.urls : []
    }
}
