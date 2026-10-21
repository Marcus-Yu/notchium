import NotchiumDesignSystem
import NotchiumDynamicIsland
import SwiftUI

/// The page and completion banner share both the available actions and their appearance.
struct PomodoroControlsView: View {
    let model: PomodoroModel
    var identifierPrefix = "notchium.pomodoro"
    var centersPrimary = false
    var compact = false
    @NotchReducedMotion private var reduceMotion

    var body: some View {
        let controls = model.state.controls
        let primary = controls.first(where: \.isPrimary)
        Group {
            if centersPrimary, let primary, let index = controls.firstIndex(of: primary) {
                PomodoroCenteredControlsLayout(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Array(controls[..<index])) { control in
                            controlButton(control, primary: false)
                        }
                    }
                    controlButton(primary, primary: true)
                    HStack(spacing: 8) {
                        ForEach(Array(controls[(index + 1)...])) { control in
                            controlButton(control, primary: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
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
                .font(.system(size: compact ? 11 : (primary ? 13 : 12),
                              weight: primary ? .bold : .semibold, design: .rounded))
                .foregroundStyle(primary ? .black.opacity(0.85) : .white.opacity(0.85))
                .padding(.horizontal, compact ? 10 : 12)
                .frame(minWidth: compact ? nil : (primary ? 88 : 72))
                .frame(height: compact ? 28 : 36)
                .background(primary ? accent : .white.opacity(0.10), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .accessibilityIdentifier("\(identifierPrefix).\(primary ? "primary" : control.rawValue)")
    }
}

/// Equal space on either side keeps the primary centered, with each secondary 8 pt beside it.
private struct PomodoroCenteredControlsLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: sizes[1].width + 2 * (max(sizes[0].width, sizes[2].width) + spacing),
                      height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let primaryWidth = subviews[1].sizeThatFits(.unspecified).width
        subviews[0].place(at: CGPoint(x: bounds.midX - primaryWidth / 2 - spacing, y: bounds.midY),
                          anchor: .trailing, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
        subviews[2].place(at: CGPoint(x: bounds.midX + primaryWidth / 2 + spacing, y: bounds.midY),
                          anchor: .leading, proposal: .unspecified)
    }
}
