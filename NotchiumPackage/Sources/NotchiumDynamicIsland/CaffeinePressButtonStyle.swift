import SwiftUI

/// One press owns both outcomes; completion consumes the later mouse-up.
struct CaffeinePressState {
    static let duration: Duration = .milliseconds(750)
    private(set) var startedAt: ContinuousClock.Instant?
    private(set) var completed = false

    mutating func begin(at instant: ContinuousClock.Instant) {
        startedAt = instant
        completed = false
    }

    mutating func complete(at instant: ContinuousClock.Instant) -> Bool {
        guard let startedAt, !completed,
              startedAt.duration(to: instant) >= Self.duration else { return false }
        completed = true
        return true
    }

    mutating func end() -> Bool {
        let click = startedAt != nil && !completed
        startedAt = nil
        return click
    }

    mutating func cancel() { startedAt = nil }
}

struct CaffeinePressButtonStyle: PrimitiveButtonStyle {
    let allowsHold: Bool
    let holdAction: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, allowsHold: allowsHold, holdAction: holdAction)
    }

    private struct PressBody: View {
        let configuration: Configuration
        let allowsHold: Bool
        let holdAction: () -> Void
        @Environment(\.isEnabled) private var isEnabled
        @State private var press = CaffeinePressState()
        @State private var holdTask: Task<Void, Never>?
        @State private var progress = 0.0
        @State private var feedback = false
        @GestureState private var isPressing = false

        var body: some View {
            configuration.label
                .overlay {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .contentShape(.circle)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressing) { _, state, _ in state = true }
                        .onChanged { value in
                            guard isEnabled else { return }
                            guard contains(value.location) else { cancel(); return }
                            // Do not restart a press after dragging out and back in.
                            guard press.startedAt == nil, holdTask == nil else { return }
                            press.begin(at: .now)
                            guard allowsHold else { return }
                            withAnimation(.linear(duration: 0.75)) { progress = 1 }
                            holdTask = Task { @MainActor in
                                guard let start = press.startedAt else { return }
                                do { try await ContinuousClock().sleep(until: start + CaffeinePressState.duration) }
                                catch { return }
                                if press.complete(at: .now) {
                                    feedback.toggle()
                                    holdAction()
                                }
                            }
                        }
                        .onEnded { value in
                            // Resolve the deadline here as well if the timer and release arrive together.
                            if contains(value.location), allowsHold, press.complete(at: .now) {
                                feedback.toggle()
                                holdAction()
                            }
                            let click = press.end()
                            if click && contains(value.location) && isEnabled { configuration.trigger() }
                            reset()
                        }
                )
                .onChange(of: isPressing) { _, pressing in
                    if !pressing { cancel(); reset() }
                }
                .onDisappear { cancel(); reset() }
                .sensoryFeedback(.alignment, trigger: feedback)
                .accessibilityAction { if isEnabled { configuration.trigger() } }
                .accessibilityAction(named: "Keep Mac and display awake") {
                    if isEnabled { holdAction() }
                }
        }

        private func contains(_ point: CGPoint) -> Bool {
            CGRect(x: 0, y: 0, width: 28, height: 28).contains(point)
        }

        private func cancel() {
            press.cancel()
            holdTask?.cancel()
            withAnimation(.easeOut(duration: 0.12)) { progress = 0 }
        }

        private func reset() {
            holdTask?.cancel()
            holdTask = nil
            withAnimation(.easeOut(duration: 0.12)) { progress = 0 }
        }
    }
}
