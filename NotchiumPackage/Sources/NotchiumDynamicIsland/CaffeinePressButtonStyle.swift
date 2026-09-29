import AppKit
import SwiftUI

struct CaffeinePressButtonStyle: PrimitiveButtonStyle {
    let interaction: CaffeinePressInteraction
    let allowsHold: Bool
    let holdAction: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, interaction: interaction,
                  allowsHold: allowsHold, holdAction: holdAction)
    }

    private struct PressBody: View {
        let configuration: Configuration
        let interaction: CaffeinePressInteraction
        let allowsHold: Bool
        let holdAction: () -> Void
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .overlay {
                    Circle()
                        .trim(from: 0, to: interaction.progress)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                        .transaction { $0.animation = nil }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay {
                    CaffeinePointerInput(interaction: interaction, isEnabled: isEnabled,
                                         allowsHold: allowsHold, click: configuration.trigger,
                                         hold: holdAction)
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
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let input, input.isEnabled else { return }
            activeInteraction = input.interaction
            input.interaction.begin(allowsHold: input.allowsHold, click: input.click, hold: input.hold)
        }
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
