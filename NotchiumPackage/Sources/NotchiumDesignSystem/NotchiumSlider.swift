import AppKit
import SwiftUI

/// A compact pointer-first slider that keeps gesture tracking separate from command handling.
public struct NotchiumSlider: View {
    @Binding private var value: Double

    private let bounds: ClosedRange<Double>
    private let accessibilityLabel: String
    private let accessibilityStep: Double
    private let accessibilityValue: (Double) -> String
    private let onEditingChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var isDragging = false

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        accessibilityLabel: String,
        accessibilityStep: Double,
        accessibilityValue: @escaping (Double) -> String,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _value = value
        self.bounds = bounds
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityStep = accessibilityStep
        self.accessibilityValue = accessibilityValue
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        GeometryReader { proxy in
            let active = isHovered || isDragging
            let horizontalInset = 5.0
            let trackWidth = max(1, proxy.size.width - horizontalInset * 2)
            let fraction = normalizedValue
            let thumbSize = isDragging ? 10.0 : active ? 8.0 : 5.0

            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(active ? 0.24 : 0.16))
                        .frame(width: trackWidth, height: active ? 3 : 2)

                    Capsule()
                        .fill(.white.opacity(isEnabled ? (active ? 1 : 0.86) : 0.45))
                        .frame(width: trackWidth * fraction, height: active ? 3 : 2)
                        .animation(nil, value: value)

                    Circle()
                        .fill(.white.opacity(isEnabled ? 1 : 0.55))
                        .frame(width: thumbSize, height: thumbSize)
                        .glassEffect(.clear, in: .circle)
                        .shadow(color: .black.opacity(active ? 0.35 : 0.2), radius: active ? 2 : 1, y: 1)
                        .opacity(active ? 1 : 0.55)
                        .offset(x: trackWidth * fraction - thumbSize / 2)
                        .animation(nil, value: value)
                }
                .frame(width: trackWidth, height: proxy.size.height)
                .offset(x: horizontalInset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .animation(interactionAnimation, value: active)
            .contentShape(.rect)
            .overlay {
                SliderPointerInput(isEnabled: isEnabled, editing: { editing in
                    isDragging = editing
                    onEditingChanged(editing)
                }, update: { location, width in
                    updateValue(at: location, width: width, inset: horizontalInset)
                })
                .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 20)
        .contentShape(.rect)
        .opacity(isEnabled ? 1 : 0.48)
        .onHover { hovering in
            isHovered = isEnabled && hovering
        }
        .focusable(isEnabled)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard isEnabled else { return .ignored }
            adjust(by: press.key == .rightArrow || press.key == .upArrow ? accessibilityStep : -accessibilityStep)
            return .handled
        }
        .accessibilityRepresentation {
            Slider(value: Binding(get: { value }, set: { candidate in
                guard isEnabled else { return }
                onEditingChanged(true)
                value = clamp(candidate)
                onEditingChanged(false)
            }), in: bounds) {
                Text(accessibilityLabel)
            }
            .disabled(!isEnabled)
            .accessibilityValue(accessibilityValue(value))
            .accessibilityAdjustableAction { direction in
                guard isEnabled else { return }
                adjust(by: direction == .increment ? accessibilityStep : -accessibilityStep)
            }
        }
    }

    private func adjust(by delta: Double) {
        onEditingChanged(true)
        value = clamp(value + delta)
        onEditingChanged(false)
    }

    private var normalizedValue: Double {
        let distance = bounds.upperBound - bounds.lowerBound
        guard distance.isFinite, distance > 0 else { return 0 }
        return min(max((value - bounds.lowerBound) / distance, 0), 1)
    }

    private var interactionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.16)
    }

    private func updateValue(at location: CGFloat, width: CGFloat, inset: CGFloat) {
        let usableWidth = max(1, width - inset * 2)
        let fraction = min(max((location - inset) / usableWidth, 0), 1)
        value = bounds.lowerBound + Double(fraction) * (bounds.upperBound - bounds.lowerBound)
    }

    private func clamp(_ candidate: Double) -> Double {
        min(max(candidate, bounds.lowerBound), bounds.upperBound)
    }
}

/// Local responder tracking works in the non-key notch panel and never observes sibling controls.
private struct SliderPointerInput: NSViewRepresentable {
    let isEnabled: Bool
    let editing: (Bool) -> Void
    let update: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> PointerView { PointerView() }
    func updateNSView(_ view: PointerView, context: Context) {
        view.input = self
        if !isEnabled { view.finish() }
    }
    static func dismantleNSView(_ view: PointerView, coordinator: ()) { view.finish() }

    final class PointerView: NSView {
        var input: SliderPointerInput?
        private var tracking = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let input, input.isEnabled else { return }
            tracking = true
            input.editing(true)
            update(event)
        }
        override func mouseDragged(with event: NSEvent) {
            guard tracking else { return }
            update(event)
        }
        override func mouseUp(with event: NSEvent) {
            guard tracking else { return }
            update(event)
            finish()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { finish() }
        }
        private func update(_ event: NSEvent) {
            input?.update(convert(event.locationInWindow, from: nil).x, bounds.width)
        }
        func finish() {
            guard tracking else { return }
            tracking = false
            input?.editing(false)
        }
    }
}
