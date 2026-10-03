import NotchiumDynamicIsland
import SwiftUI

/// A small next-step surface inside the shell's existing downward notification reveal.
struct PomodoroCompletionView: View {
    let model: PomodoroModel
    let title: String
    let openTimer: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: PomodoroStyle.symbol(model.state.phase))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PomodoroStyle.accent(model.state.phase))
                    .accessibilityHidden(true)
                Button(action: openTimer) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text("\(model.state.phase.title) · \(NotchCountdown.label(model.countdown().remaining(at: .now)))")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Focus Timer, \(title)")
                .accessibilityIdentifier("notchium.pomodoro.completion.open")
                Button(action: model.dismissCompletion) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Dismiss timer completion")
                .accessibilityLabel("Dismiss timer completion")
                .accessibilityIdentifier("notchium.pomodoro.completion.dismiss")
            }
            PomodoroControlsView(model: model, identifierPrefix: "notchium.pomodoro.completion", centersPrimary: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, NotchNotificationGeometry.contentHorizontalInset)
        .frame(height: NotchNotificationGeometry.pomodoroCompletionHeight)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Dismiss timer completion", model.dismissCompletion)
        .accessibilityIdentifier("notchium.pomodoro.completion")
    }
}
