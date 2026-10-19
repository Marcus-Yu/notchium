import AppKit
import SwiftUI

/// A normal key window stays below system consent dialogs, including in fullscreen Spaces.
@MainActor final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var dismissing = false
    init(model: OnboardingModel, enterApp: @escaping () -> Void) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Welcome to Notchium"
        window.identifier = NSUserInterfaceItemIdentifier("notchium.onboarding")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 520)
        window.level = .normal
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.contentView = NSHostingView(rootView: OnboardingView(model: model, enterApp: enterApp))
        window.delegate = self
        window.center()
    }
    func show() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func dismiss() {
        dismissing = true
        window.close()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if dismissing { return true }
        NSApp.terminate(nil)
        return false
    }
}
