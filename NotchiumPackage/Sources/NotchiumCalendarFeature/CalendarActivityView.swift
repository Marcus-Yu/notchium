import AppKit
import NotchiumDynamicIsland
import NotchiumServices
import SwiftUI

public struct CalendarActivityView: View {
    @Bindable var model: CalendarActivityModel
    @Environment(\.notchCalendarPageVisible) private var isPageVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
        GeometryReader { geometry in
            let columnWidth = geometry.size.width - 14
            HStack(alignment: .top, spacing: 14) {
                mainEvent(event)
                    .frame(width: columnWidth * 0.54, height: geometry.size.height)
                upcomingEvents
                    .frame(width: columnWidth * 0.46, height: geometry.size.height)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func mainEvent(_ event: CalendarEventSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(color(event.calendarColor)).frame(width: 5, height: 5)
                Text(event.calendarName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Text(event.title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(CalendarEventText.timeRange(event))
                    .foregroundStyle(.white.opacity(0.65))
                Group {
                    if isPageVisible {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(countdown(event, at: context.date))
                        }
                    } else {
                        Text(countdown(event, at: .now))
                    }
                }
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
            }
            .font(.system(size: 11))
            .padding(.top, 6)
            if let detail = CalendarEventText.detail(event) {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .padding(.top, 6)
            }
            if event.meetingURL != nil {
                Spacer(minLength: 6)
                Button { model.joinEvent(event.id) } label: {
                    Label("Join", systemImage: "video.fill")
                }
                .buttonStyle(CalendarJoinButtonStyle())
                .controlSize(.small)
                .accessibilityIdentifier("notchium.calendar.join")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: event.meetingURL == nil ? .leading : .topLeading)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.09))
            }
        }
        .glassEffect(reduceTransparency ? .identity : .clear, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("notchium.calendar.main")
    }

    private var upcomingEvents: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("UP NEXT")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.48))
                .padding(.horizontal, 8)
            if model.secondaryEvents.isEmpty {
                Text("No more upcoming events")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(8)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.secondaryEvents) { item in
                                CalendarUpcomingEventRow(event: item,
                                    isExpanded: model.selectedEventID == item.id,
                                    toggle: { model.toggleEvent(item.id) },
                                    join: { model.joinEvent(item.id) })
                                    .id(item.id)
                            }
                        }
                        .animation(expansionAnimation, value: model.selectedEventID)
                    }
                    .onChange(of: model.selectedEventID) { _, id in
                        if let id {
                            withAnimation(expansionAnimation) { scroll.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var expansionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.25)
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
