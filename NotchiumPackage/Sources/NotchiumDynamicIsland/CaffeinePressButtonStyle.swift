import AppKit
import NotchiumCore
import SwiftUI

struct CaffeinePressButtonStyle: PrimitiveButtonStyle {
    let interaction: CaffeinePressInteraction
    let allowsHold: Bool
    let holdAction: () -> Void
    var selectedDuration: CaffeineDuration? = nil
    var durationAction: ((CaffeineDuration) -> Void)? = nil
    var closedLidApproval: (() -> Void)? = nil
    var hoverAction: ((Bool) -> Void)? = nil

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, interaction: interaction,
                  allowsHold: allowsHold, holdAction: holdAction,
                  selectedDuration: selectedDuration, durationAction: durationAction,
                  closedLidApproval: closedLidApproval, hoverAction: hoverAction)
    }

    private struct PressBody: View {
        let configuration: Configuration
        let interaction: CaffeinePressInteraction
        let allowsHold: Bool
        let holdAction: () -> Void
        let selectedDuration: CaffeineDuration?
        let durationAction: ((CaffeineDuration) -> Void)?
        let closedLidApproval: (() -> Void)?
        let hoverAction: ((Bool) -> Void)?
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .overlay {
                    if allowsHold, interaction.progress > 0 {
                        Circle()
                            .trim(from: 0, to: interaction.progress)
                            .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(1)
                            .transaction { $0.animation = nil }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .overlay {
                    CaffeinePointerInput(interaction: interaction, isEnabled: isEnabled,
                                         allowsHold: allowsHold, click: configuration.trigger,
                                         hold: holdAction, selectedDuration: selectedDuration,
                                         durationAction: durationAction, closedLidApproval: closedLidApproval,
                                         hoverAction: hoverAction)
                        .accessibilityHidden(true)
                }
                .sensoryFeedback(.alignment, trigger: interaction.completionCount)
                .accessibilityAction { if isEnabled { configuration.trigger() } }
                .accessibilityAction(named: "Keep Mac and display awake") {
                    if isEnabled { holdAction() }
                }
        }
    }
}

/// AppKit delivers a single down/drag/up sequence without SwiftUI gesture-state resets.
struct CaffeinePointerInput: NSViewRepresentable {
    let interaction: CaffeinePressInteraction
    let isEnabled: Bool
    let allowsHold: Bool
    let click: () -> Void
    let hold: () -> Void
    var selectedDuration: CaffeineDuration? = nil
    var durationAction: ((CaffeineDuration) -> Void)? = nil
    var closedLidApproval: (() -> Void)? = nil
    var hoverAction: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> PressView { PressView() }
    func updateNSView(_ view: PressView, context: Context) {
        view.input = self
    }
    static func dismantleNSView(_ view: PressView, coordinator: ()) {
        view.cancelPress()
    }

    final class PressView: NSView {
        var input: CaffeinePointerInput?
        private var activeInteraction: CaffeinePressInteraction?
        private var hoverTrackingArea: NSTrackingArea?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            guard hoverTrackingArea == nil else { return }
            let area = NSTrackingArea(rect: .zero,
                                      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            hoverTrackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { input?.hoverAction?(true) }
        override func mouseExited(with event: NSEvent) { input?.hoverAction?(false) }

        override func mouseDown(with event: NSEvent) {
            guard let input, input.isEnabled else { return }
            if event.modifierFlags.contains(.control) {
                showDurationMenu(with: event)
                return
            }
            activeInteraction = input.interaction
            input.interaction.begin(allowsHold: input.allowsHold, click: input.click, hold: input.hold)
        }
        override func rightMouseDown(with event: NSEvent) {
            showDurationMenu(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard let input, input.isEnabled, input.durationAction != nil else { return nil }
            let menu = NSMenu(title: "Keep Awake For")
            for duration in CaffeineDuration.allCases {
                let item = NSMenuItem(title: duration.title, action: #selector(selectDuration(_:)), keyEquivalent: "")
                item.target = self
                item.tag = duration.rawValue
                item.state = input.selectedDuration == duration ? .on : .off
                menu.addItem(item)
            }
            if input.closedLidApproval != nil {
                menu.addItem(.separator())
                let approval = NSMenuItem(title: "Approve Closed-Lid Support…", action: #selector(approveClosedLid),
                                          keyEquivalent: "")
                approval.target = self
                menu.addItem(approval)
            }
            return menu
        }

        private func showDurationMenu(with event: NSEvent) {
            cancelPress()
            guard let menu = menu(for: event) else { return }
            // Native menu tracking already participates in the panel's auxiliary retention.
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func selectDuration(_ item: NSMenuItem) {
            guard let input, input.isEnabled, let duration = CaffeineDuration(rawValue: item.tag) else { return }
            input.durationAction?(duration)
        }

        @objc private func approveClosedLid() { input?.closedLidApproval?() }
        override func mouseDragged(with event: NSEvent) {
            // Native-style hysteresis tolerates ordinary trackpad/mouse movement.
            if !containsPress(event) { cancelPress() }
        }
        override func mouseUp(with event: NSEvent) {
            if containsPress(event) { activeInteraction?.end() }
            else { activeInteraction?.cancel() }
            activeInteraction = nil
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { cancelPress() }
        }
        private func containsPress(_ event: NSEvent) -> Bool {
            bounds.insetBy(dx: -10, dy: -10).contains(convert(event.locationInWindow, from: nil))
        }
        func cancelPress() {
            activeInteraction?.cancel()
            activeInteraction = nil
        }
    }
}
