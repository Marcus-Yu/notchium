import AppKit

/// A small, explicit source for ShareKit. Dimming this window never dims the transparent
/// 740-point notch host. It also gives standalone system UI a visible return/cancel path.
@MainActor
final class NativeShareWindow: NSPanel {
    var onCancel: (() -> Void)?
    private weak var origin: NSWindow?

    init(origin: NSWindow?) {
        self.origin = origin
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 86),
                   styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Sharing — Notchium"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        let label = NSTextField(wrappingLabelWithString: "Finish or cancel in the sharing window.")
        let button = NSButton(title: "Cancel and Return to Shelf", target: self, action: #selector(cancelSharing))
        button.keyEquivalent = "\u{1b}"
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(stack)
        if let contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                stack.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -24),
            ])
        }
        if let screen = origin?.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: frame.midX - self.frame.width / 2, y: frame.midY - self.frame.height / 2))
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func performClose(_ sender: Any?) { onCancel?() }
    @objc private func cancelSharing() { onCancel?() }
}
