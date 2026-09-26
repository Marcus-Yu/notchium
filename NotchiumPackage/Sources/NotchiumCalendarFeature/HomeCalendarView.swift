import SwiftUI
import NotchiumServices

/// Date-dependent projection only; EventKit ownership stays in CalendarService.
struct HomeCalendarSummary {
    let nextEvent: CalendarEventSummary?
    let hasEventsToday: Bool

    init(events: [CalendarEventSummary], at date: Date, calendar: Calendar = .current) {
        let remaining = events.filter { $0.endDate > date }
        nextEvent = remaining.min { $0.startDate < $1.startDate }
        let today = calendar.dateInterval(of: .day, for: date)
        hasEventsToday = remaining.contains { event in
            guard let today else { return false }
            return event.startDate < today.end && event.endDate > today.start
        }
    }
}

struct HomeCalendarView: View {
    let model: CalendarActivityModel
    let openCalendar: @MainActor () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HomeCalendarContent(snapshot: model.snapshot, date: timeline.date, openCalendar: openCalendar)
        }
    }
}

struct HomeCalendarContent: View {
    let snapshot: CalendarSnapshot
    let date: Date
    let openCalendar: @MainActor () -> Void

    var body: some View {
        let summary = HomeCalendarSummary(events: snapshot.upcomingEvents, at: date)
        Button(action: openCalendar) {
            VStack(alignment: .leading, spacing: 0) {
                Text(date.formatted(.dateTime.month(.wide).year()).uppercased())
                    .font(.system(size: 9, weight: .medium)).tracking(0.7)
                    .foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(date.formatted(.dateTime.day())).font(.system(size: 34, weight: .light, design: .rounded))
                    Text(date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }.padding(.top, 3)
                Rectangle().fill(.white.opacity(0.1)).frame(height: 1).padding(.vertical, 12)
                if snapshot.permission != .granted {
                    status("Set up Calendar", detail: "Open Calendar to get started.")
                } else if snapshot.availability != .available {
                    status("Calendar unavailable", detail: "Open Calendar to check access.")
                } else if let event = summary.nextEvent {
                    Text(summary.hasEventsToday ? "NEXT EVENT" : "NO EVENTS TODAY")
                        .font(.system(size: 8, weight: .medium)).tracking(0.5)
                        .foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(2).padding(.top, 5)
                    Text(eventTime(event)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1).padding(.top, 4)
                } else {
                    status("No events today", detail: "Enjoy your free time.")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .accessibilityIdentifier("notchium.home.calendar")
        .accessibilityHint("Open Calendar")
    }

    private func status(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(2)
            Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(2)
        }
    }

    private func eventTime(_ event: CalendarEventSummary) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDate(event.startDate, inSameDayAs: date) { day = "Today" }
        else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date),
                calendar.isDate(event.startDate, inSameDayAs: tomorrow) { day = "Tomorrow" }
        else { day = event.startDate.formatted(.dateTime.month(.abbreviated).day()) }
        return day + " · " + (event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
    }
}
