import NotchiumCore
import SwiftUI

struct NotchCaffeineButton: View {
    let controller: any NotchCaffeineControlling

    @State private var isHovered = false
    @Environment(\.notchMediaExpanded) private var isExpanded

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isTimed || !isExpanded)) { context in
            button(countdown: countdown(at: context.date))
        }
        .disabled(controller.isBusy)
        .onDisappear { isHovered = false }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .accessibilityLabel("Caffeine")
        .accessibilityHint("Click to keep Mac and display awake until turned off. Right-click or press Down Arrow to choose a duration.")
        .accessibilityActions {
            ForEach(CaffeineDuration.allCases) { duration in
                Button(duration.title) { controller.keepAwake(for: duration) }
                    .disabled(controller.isBusy)
            }
        }
        .accessibilityIdentifier("notchium.shell.caffeine")
    }

    private func button(countdown: CaffeineCountdown?) -> some View {
        Button(action: controller.cycleMode) {
            CaffeineShortcutLabel(isActive: controller.mode.isActive, isHovered: isHovered,
                                  progress: countdown?.elapsedProgress)
        }
        .buttonStyle(pressStyle)
        .help(countdown == nil ? tooltip : "")
        .overlay(alignment: .topTrailing) {
            if isHovered, let countdown {
                CaffeineRemainingTimeLabel(text: countdown.remainingLabel)
                    .offset(y: 34)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(accessibilityValue + (countdown.map { " · \($0.remainingLabel)" } ?? ""))
    }

    private var pressStyle: CaffeinePressButtonStyle {
        let approval: (() -> Void)? = controller.needsClosedLidApproval
            ? { controller.openClosedLidApproval() } : nil
        return CaffeinePressButtonStyle(interaction: controller.pressInteraction, allowsHold: false,
                                        holdAction: controller.keepDisplayAwake,
                                        selectedDuration: controller.selectedDuration,
                                        durationAction: { controller.keepAwake(for: $0) },
                                        closedLidApproval: approval,
                                        hoverAction: { isHovered = $0 })
    }

    private var isTimed: Bool {
        controller.mode.isActive && controller.selectedDuration != nil && controller.expiresAt != nil
    }

    private func countdown(at date: Date) -> CaffeineCountdown? {
        guard isTimed, let duration = controller.selectedDuration, let expiresAt = controller.expiresAt else { return nil }
        return CaffeineCountdown(duration: duration, expiresAt: expiresAt, now: date)
    }

    private var tooltip: String {
        if let message = controller.statusMessage { return message }
        return controller.mode.isActive
            ? "Mac + Display Awake · Click to turn off"
            : "Keep Mac + Display Awake · Right-click for duration"
    }

    private var accessibilityValue: String {
        switch controller.mode {
        case .off: "Off"
        case .system: "Keeping Mac awake"
        case .systemAndDisplay: "Keeping Mac and display awake"
        }
    }
}

/// Active sessions use a solid orange symbol; only timed sessions get a border.
struct CaffeineShortcutLabel: View {
    let isActive: Bool
    let isHovered: Bool
    let progress: Double?
    private let activeColor = Color(red: 1, green: 172.0 / 255.0, blue: 28.0 / 255.0)

    var body: some View {
        NotchUtilityLabel(symbol: "cup.and.saucer.fill", isHovered: isHovered,
                          foreground: isActive ? activeColor : nil)
            .symbolRenderingMode(.monochrome)
            .overlay {
                if isActive, let progress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(activeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                        .transaction { $0.animation = nil }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct CaffeineRemainingTimeLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(white: 0.16), in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
            .fixedSize()
            .accessibilityIdentifier("notchium.shell.caffeine.remaining")
    }
}

/// Both the border and hover label derive from the model's existing expiry.
struct CaffeineCountdown {
    let elapsedProgress: Double
    let remainingSeconds: Int

    init(duration: CaffeineDuration, expiresAt: Date, now: Date) {
        let total = Double(duration.rawValue * 60)
        let remaining = min(total, max(0, expiresAt.timeIntervalSince(now)))
        elapsedProgress = 1 - remaining / total
        remainingSeconds = Int(ceil(remaining))
    }

    var remainingLabel: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return "\(minutes):\(seconds.formatted(.number.precision(.integerLength(2)))) remaining"
    }
}
