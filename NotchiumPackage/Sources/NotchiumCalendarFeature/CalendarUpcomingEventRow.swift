import NotchiumServices
import SwiftUI

/// Disclosure and Join are sibling buttons, so joining never toggles the row.
struct CalendarUpcomingEventRow: View {
    let event: CalendarEventSummary
    let isExpanded: Bool
    let toggle: () -> Void
    let join: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CalendarEventText.timeRange(event, includesDay: true))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    if isExpanded {
                        if let detail = CalendarEventText.detail(event) {
                            Text(detail)
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                        if event.meetingURL != nil {
                            // Reserve a separate action row so Join never crowds the title or details.
                            Color.clear.frame(height: 28)
                        }
                    }
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse event details" : "Expand event details")
            .accessibilityIdentifier("notchium.calendar.event.\(event.id)")

            if isExpanded && event.meetingURL != nil {
                Button(action: join) {
                    Label("Join", systemImage: "video.fill")
                }
                .buttonStyle(CalendarJoinButtonStyle())
                .controlSize(.small)
                .accessibilityLabel("Join \(event.title)")
                .accessibilityIdentifier("notchium.calendar.event.join.\(event.id)")
                .padding(7)
                .transition(.opacity)
            }
        }
        .background(.white.opacity(isExpanded ? 0.09 : (isHovered ? 0.065 : 0.025)),
                    in: RoundedRectangle(cornerRadius: isExpanded ? 10 : 6))
        .onHover { isHovered = $0 }
    }
}
