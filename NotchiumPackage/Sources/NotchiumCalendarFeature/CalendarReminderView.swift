import NotchiumDynamicIsland
import SwiftUI

struct CalendarReminderView: View {
    @Bindable var model: CalendarActivityModel
    @State private var isHovered = false

    var body: some View {
        if let reminder = model.reminders.current {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Button(action: model.openReminder) {
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color(red: reminder.event.calendarColor.red,
                                            green: reminder.event.calendarColor.green,
                                            blue: reminder.event.calendarColor.blue))
                                .frame(width: 5, height: 5)
                                .padding(.top, 5.5)
                                .padding(.trailing, 1)
                            Text(reminder.event.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            Text(reminder.label)
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.66))
                                .fixedSize()
                                .padding(.top, 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Calendar for \(reminder.event.title)")

                    // Reserve the dismiss target so hovering never reflows the title.
                    Button(action: model.dismissReminder) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(width: 18, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
                    .accessibilityHidden(!isHovered)
                    .accessibilityLabel("Dismiss Calendar reminder")
                    .accessibilityIdentifier("notchium.calendar.reminder.dismiss")
                }

                if reminder.event.meetingURL != nil {
                    Button(action: model.joinReminder) {
                        HStack(spacing: 5) {
                            Image(systemName: "video.fill")
                            Text(reminder.isNow ? "Join Now" : "Join")
                        }
                    }
                    .buttonStyle(CalendarJoinButtonStyle(height: 26))
                    .help(reminder.isNow ? "Join meeting now" : "Join meeting")
                    .accessibilityIdentifier("notchium.calendar.reminder.join")
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                if !reminder.isImminent, let location = reminder.event.location {
                    Button(action: model.openReminder) {
                        Text(location)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.50))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity,
                                   alignment: reminder.event.meetingURL == nil ? .leading : .center)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, reminder.event.meetingURL == nil ? 16 : 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: NotchReminderGeometry.minimumHeight)
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
