import NotchiumDynamicIsland
import SwiftUI

struct CalendarReminderView: View {
    @Bindable var model: CalendarActivityModel
    let openActivity: @MainActor () -> Void
    @State private var isHovered = false

    var body: some View {
        if let reminder = model.reminders.current {
            HStack(spacing: 12) {
                Button(action: openActivity) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(reminder.event.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(reminder.label)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Calendar for \(reminder.event.title), \(reminder.label)")

                if reminder.event.meetingURL != nil {
                    Button(action: model.joinReminder) {
                        Label(reminder.isNow ? "Join Now" : "Join", systemImage: "video.fill")
                    }
                    .buttonStyle(NotificationJoinButtonStyle(prominent: reminder.isImminent))
                    .help("Join meeting")
                    .accessibilityIdentifier("notchium.calendar.reminder.join")
                }

                Button(action: model.dismissReminder) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(isHovered ? 0.85 : 0.5))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss reminder")
                .accessibilityLabel("Dismiss Calendar reminder")
                .accessibilityIdentifier("notchium.calendar.reminder.dismiss")
            }
            .padding(.leading, NotchNotificationGeometry.contentLeadingInset)
            .padding(.trailing, NotchNotificationGeometry.contentHorizontalInset)
            .padding(.vertical, 16)
            .frame(height: NotchReminderGeometry.minimumHeight)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .onHover { isHovered = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Dismiss reminder", model.dismissReminder)
            .accessibilityIdentifier("notchium.calendar.reminder")
        }
    }
}

private struct NotificationJoinButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                if prominent {
                    Capsule().fill(.white.opacity(configuration.isPressed ? 0.8 : 1))
                } else if reduceTransparency {
                    Capsule().fill(.white.opacity(configuration.isPressed ? 0.75 : 0.9))
                } else {
                    Capsule().fill(.white.opacity(0.9))
                        .glassEffect(.clear.interactive(), in: .capsule)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
