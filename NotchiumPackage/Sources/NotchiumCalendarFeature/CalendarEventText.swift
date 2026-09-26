import Foundation
import NotchiumServices

/// Display formatting only; meeting validation remains in MeetingLinkDetector.
enum CalendarEventText {
    static func timeRange(_ event: CalendarEventSummary, includesDay: Bool = false) -> String {
        let day = includesDay && !Calendar.current.isDateInToday(event.startDate)
            ? event.startDate.formatted(.dateTime.weekday(.abbreviated)) + " · " : ""
        let range = event.isAllDay ? "All day" :
            "\(event.startDate.formatted(date: .omitted, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))"
        return day + range
    }

    static func detail(_ event: CalendarEventSummary) -> String? {
        if let location = event.location, !location.isEmpty { return location }
        guard let host = event.meetingURL?.host?.lowercased() else { return nil }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") { return "Zoom" }
        if host == "meet.google.com" { return "Google Meet" }
        if host == "teams.microsoft.com" || host == "teams.live.com" || host == "teams.cloud.microsoft" {
            return "Microsoft Teams"
        }
        return host
    }
}
