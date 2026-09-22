import NotchiumDynamicIsland
import SwiftUI

struct CalendarReminderView: View {
    @Bindable var model: CalendarActivityModel
    @State private var isHovered = false

    var body: some View {
        if let reminder = model.reminders.current {
            HStack(spacing: 12) {
                Button(action: model.openReminder) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(red: reminder.event.calendarColor.red,
                                        green: reminder.event.calendarColor.green,
                                        blue: reminder.event.calendarColor.blue))
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.event.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            if !reminder.isImminent, let location = reminder.event.location {
                                Text(location)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.54))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 2)
                        Text(reminder.label)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Calendar for \(reminder.event.title)")

                if reminder.event.meetingURL != nil {
                    Button(action: model.joinReminder) {
                        HStack(spacing: 5) {
                            Image(systemName: "video.fill")
                            Text(reminder.isNow ? "Join Now" : "Join")
                        }
                    }
                    .buttonStyle(CalendarJoinButtonStyle())
                    .help(reminder.isNow ? "Join meeting now" : "Join meeting")
                    .accessibilityIdentifier("notchium.calendar.reminder.join")
                }
                if isHovered {
                    Button(action: model.dismissReminder) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss Calendar reminder")
                    .accessibilityIdentifier("notchium.calendar.reminder.dismiss")
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: NotchReminderGeometry.height)
            .background {
                Button(action: model.openReminder) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            .onHover { hovered in
                isHovered = hovered
                model.setReminderHovered(hovered)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("notchium.calendar.reminder")
        }
    }
}
