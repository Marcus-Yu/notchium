import AppKit
import SwiftUI

/// Tracks the reusable Settings window without replacing SwiftUI's window delegate.
struct SettingsWindowLifecycle: NSViewRepresentable {
    let onOpenChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onOpenChanged = onOpenChanged
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onOpenChanged = onOpenChanged
    }

    static func dismantleNSView(_ view: ObserverView, coordinator: ()) {
        view.stopObserving()
    }

    final class ObserverView: NSView {
        var onOpenChanged: (Bool) -> Void = { _ in }
        private weak var observedWindow: NSWindow?
        private var isOpen = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window !== observedWindow else { return }
            stopObserving()
            guard let window else { return }
            observedWindow = window
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(windowDidBecomeKey),
                               name: NSWindow.didBecomeKeyNotification, object: window)
            center.addObserver(self, selector: #selector(windowWillClose),
                               name: NSWindow.willCloseNotification, object: window)
            if window.isVisible || window.isMiniaturized { setOpen(true) }
        }

        func stopObserving() {
            NotificationCenter.default.removeObserver(self)
            observedWindow = nil
            setOpen(false)
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            setOpen(true)
        }

        @objc private func windowWillClose(_ notification: Notification) {
            setOpen(false)
        }

        private func setOpen(_ value: Bool) {
            guard isOpen != value else { return }
            isOpen = value
            onOpenChanged(value)
        }
    }
}
