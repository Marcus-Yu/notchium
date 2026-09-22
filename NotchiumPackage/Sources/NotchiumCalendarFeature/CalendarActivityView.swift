import AppKit
import NotchiumDynamicIsland
import NotchiumServices
import SwiftUI

public struct CalendarActivityView: View {
    @Bindable var model: CalendarActivityModel
    @Environment(\.notchCalendarPageVisible) private var isPageVisible
    public init(model: CalendarActivityModel) { self.model = model }

    public var body: some View {
        Group {
            switch model.snapshot.permission {
            case .notRequested:
                permissionView("See what’s next", detail: "Allow Notchium to read your macOS calendars.") {
                    Button("Allow Calendar Access") { model.requestAccess() }
                        .buttonStyle(.glass)
                }
            case .denied, .restricted:
                permissionView("Calendar access is off", detail: "Enable Notchium in System Settings → Privacy & Security → Calendars.") {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                    }.buttonStyle(.glass)
                }
            case .granted:
                if let event = model.snapshot.nextEvent {
                    eventContent(event)
                } else {
                    permissionView("Nothing coming up", detail: model.snapshot.calendars.contains(where: \.isSelected)
                        ? "Your selected calendars are clear for the next two weeks."
                        : "Choose calendars to monitor in Settings.") {
                        EmptyView()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .accessibilityIdentifier("notchium.calendar.page")
    }

    private func eventContent(_ event: CalendarEventSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle().fill(color(event.calendarColor)).frame(width: 6, height: 6)
                        Text(event.calendarName).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    Text(event.title).font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(event.isAllDay ? "All day" : "\(event.startDate.formatted(date: .omitted, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))")
                        if let location = event.location {
                            Text("·")
                            Text(location).lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    Group {
                        if isPageVisible {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(countdown(event, at: context.date))
                            }
                        } else {
                            Text(countdown(event, at: .now))
                        }
                    }
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.82))
                    if let url = event.meetingURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Join", systemImage: "video.fill")
                        }
                        .buttonStyle(CalendarJoinButtonStyle())
                        .controlSize(.small)
                        .accessibilityIdentifier("notchium.calendar.join")
                    }
                }
            }
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            Text("UP NEXT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.48))
            VStack(spacing: 5) {
                ForEach(Array(model.snapshot.upcomingEvents.dropFirst().prefix(4))) { item in
                    HStack(spacing: 8) {
                        Circle().fill(color(item.calendarColor)).frame(width: 5, height: 5)
                        Text(item.title).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(item.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .font(.system(size: 11))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func permissionView<Action: View>(_ title: String, detail: String,
                                                 @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 20))
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            action()
        }
        .padding(.horizontal, 40)
    }
}

private func color(_ value: CalendarColor) -> Color {
    Color(red: value.red, green: value.green, blue: value.blue)
}

private func countdown(_ event: CalendarEventSummary, at date: Date) -> String {
    switch event.status(at: date) {
    case .upcoming, .startingSoon:
        let seconds = max(0, Int(event.startDate.timeIntervalSince(date).rounded(.up)))
        if seconds < 60 { return "In \(seconds)s" }
        if seconds < 3600 { return "In \(Int(ceil(Double(seconds) / 60)))m" }
        return "In \(Int(ceil(Double(seconds) / 3600)))h" 
    case .now: return "Now"
    case .inProgress:
        let minutes = max(1, Int(ceil(event.endDate.timeIntervalSince(date) / 60)))
        return "\(minutes)m left"
    case .ended: return "Ended"
    }
}
