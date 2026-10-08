import NotchiumDesignSystem
import NotchiumDynamicIsland
import SwiftUI

/// The page and completion banner share both the available actions and their appearance.
struct PomodoroControlsView: View {
    let model: PomodoroModel
    var identifierPrefix = "notchium.pomodoro"
    var centersPrimary = false
    @NotchReducedMotion private var reduceMotion

    var body: some View {
        let controls = model.state.controls
        let primary = controls.first(where: \.isPrimary)
        Group {
            if centersPrimary, let primary, let index = controls.firstIndex(of: primary) {
                ZStack {
                    HStack(spacing: 8) {
                        ForEach(Array(controls[..<index])) { control in
                            controlButton(control, primary: false)
                        }
                        Spacer(minLength: 0)
                        ForEach(Array(controls[(index + 1)...])) { control in
                            controlButton(control, primary: false)
                        }
                    }
                    controlButton(primary, primary: true)
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(controls) { control in
                        controlButton(control, primary: control == primary)
                    }
                }
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.2), value: controls)
    }

    private func controlButton(_ control: PomodoroControl, primary: Bool) -> some View {
        let accent = PomodoroStyle.accent(model.state.phase)
        return Button { model.perform(control) } label: {
            Text(control.title)
                .font(.system(size: 11, weight: primary ? .bold : .semibold, design: .rounded))
                .foregroundStyle(primary ? .black.opacity(0.85) : .white.opacity(0.85))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(primary ? accent : .white.opacity(0.10), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .accessibilityIdentifier("\(identifierPrefix).\(primary ? "primary" : control.rawValue)")
    }
}
