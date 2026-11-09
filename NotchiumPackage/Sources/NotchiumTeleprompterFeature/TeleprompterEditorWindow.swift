import AppKit
import SwiftUI

/// One retained native editor window. Opening it ends microphone capture before taking focus.
@MainActor
public final class TeleprompterEditorWindow: NSWindowController, NSWindowDelegate {
    private let model: TeleprompterModel

    public init(model: TeleprompterModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Teleprompter Scripts"
        window.contentMinSize = NSSize(width: 780, height: 500)
        window.isReleasedWhenClosed = false
        let content = NSHostingController(rootView: TeleprompterEditorView(model: model))
        // AppKit owns this resizable window's geometry. SwiftUI's ideal text-editor
        // size must not move the title bar or document controls off screen.
        content.sizingOptions = []
        window.contentViewController = content
        window.setContentSize(NSSize(width: 940, height: 700))
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }

    public func show() {
        model.session.pause()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    public func windowWillClose(_ notification: Notification) {
        model.session.pause()
    }
}
