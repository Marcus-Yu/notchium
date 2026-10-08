import SwiftUI
import NotchiumDesignSystem
import NotchiumDynamicIsland
import NotchiumServices

/// Date-dependent projection only; EventKit ownership stays in CalendarService.
struct HomeCalendarSummary {
    let nextEvents: [CalendarEventSummary]

    init(events: [CalendarEventSummary], at date: Date) {
        nextEvents = Array(events.filter { $0.endDate > date }
            .sorted { $0.startDate < $1.startDate }.prefix(2))
    }
}

struct HomeCalendarView: View {
    let model: CalendarActivityModel
    let openCalendar: @MainActor () -> Void
    @Environment(\.notchHomePageVisible) private var isVisible

    var body: some View {
        if isVisible {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                HomeCalendarContent(snapshot: model.snapshot, date: timeline.date, openCalendar: openCalendar)
            }
        } else {
            HomeCalendarContent(snapshot: model.snapshot, date: .now, openCalendar: openCalendar)
        }
    }
}

struct HomeCalendarContent: View {
    let snapshot: CalendarSnapshot
    let date: Date
    let openCalendar: @MainActor () -> Void
    @Environment(\.homeUsesCompactLayout) private var compact

    var body: some View {
        let summary = HomeCalendarSummary(events: snapshot.upcomingEvents, at: date)
        Button(action: openCalendar) {
            VStack(alignment: .leading, spacing: 0) {
                Text(date.formatted(.dateTime.month(.wide).year()))
                    .font(compact ? .system(size: 10) : ExpandedPageStyle.caption)
                    .foregroundStyle(ExpandedPageStyle.secondary).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(date.formatted(.dateTime.day())).font(.system(size: compact ? 26 : 34, weight: .light, design: .rounded))
                    Text(date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }.padding(.top, compact ? 2 : 3)
                Rectangle().fill(.white.opacity(0.1)).frame(height: 1).padding(.vertical, compact ? ExpandedPageStyle.Space.xs : ExpandedPageStyle.groupGap)
                if snapshot.permission != .granted {
                    status("Set up Calendar", detail: "Open Calendar to get started.")
                } else if snapshot.availability != .available {
                    status("Calendar unavailable", detail: "Open Calendar to check access.")
                } else if !summary.nextEvents.isEmpty {
                    Text("Next events")
                        .font(compact ? .system(size: 10) : ExpandedPageStyle.caption)
                        .foregroundStyle(ExpandedPageStyle.secondary).lineLimit(1)
                    VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                        ForEach(summary.nextEvents) { event in
                            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                                Text(event.title).font(.system(size: compact ? 11 : 12, weight: .medium))
                                    .lineLimit(summary.nextEvents.count > 1 ? 1 : 2)
                                    .help(event.title)
                                Text(eventTime(event)).font(.system(size: 10))
                                    .foregroundStyle(ExpandedPageStyle.secondary).lineLimit(1)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, compact ? 3 : 5)
                } else {
                    status("No events today", detail: "Enjoy your free time.")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, compact ? ExpandedPageStyle.Space.xs : ExpandedPageStyle.Space.sm)
        .accessibilityIdentifier("notchium.home.calendar")
        .accessibilityHint("Open Calendar")
    }

    private func status(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text(title).font(.system(size: compact ? 11 : 12, weight: .medium)).lineLimit(2)
            Text(detail).font(.system(size: 10)).foregroundStyle(ExpandedPageStyle.secondary).lineLimit(2)
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
