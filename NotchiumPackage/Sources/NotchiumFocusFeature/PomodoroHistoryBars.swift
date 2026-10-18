import SwiftUI
import NotchiumDesignSystem

struct PomodoroMonthBars: View {
    let days: [PomodoroStatistics.Day]
    let calendar: Calendar
    @State private var hoveredDayID: Date?
    @State private var hoverLocation = CGPoint.zero

    var body: some View {
        let peak = max(days.map(\.focus).max() ?? 0, 3600)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let isToday = index == days.count - 1
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        PomodoroHistoryBar(focus: day.focus, peak: peak, isToday: isToday,
                                           isHovered: hoveredDayID == day.id)
                    }
                    .frame(width: 9)
                    .contentShape(.rect)
                    .onContinuousHover(coordinateSpace: .named("pomodoro.history.bars")) { phase in
                        switch phase {
                        case let .active(location):
                            hoveredDayID = day.id
                            hoverLocation = location
                        case .ended:
                            if hoveredDayID == day.id { hoveredDayID = nil }
                        }
                    }
                    .padding(.leading, index == 0 ? 0 : (startsWeek(day.date) ? 7 : 3.5))
                    .accessibilityElement()
                    .accessibilityLabel(description(day))
                }
            }
            .frame(height: 92, alignment: .bottom)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Focus time per day")
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Text(startsWeek(day.date) || index == 0 ? day.date.formatted(.dateTime.month(.abbreviated).day()) : "")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize()
                        .frame(width: 9, alignment: .leading)
                        .padding(.leading, index == 0 ? 0 : (startsWeek(day.date) ? 7 : 3.5))
                }
            }
            .accessibilityHidden(true)
        }
        .coordinateSpace(.named("pomodoro.history.bars"))
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if let day = days.first(where: { $0.id == hoveredDayID }) {
                    PomodoroHistoryPeek(day: day, calendar: calendar)
                        // Stay beside the pointer while keeping the peek inside the chart.
                        .offset(x: min(max(0, hoverLocation.x + 12), max(0, geometry.size.width - 128)),
                                y: min(max(0, hoverLocation.y > 56 ? hoverLocation.y - 52 : hoverLocation.y + 12),
                                       max(0, geometry.size.height - 44)))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
        .onDisappear { hoveredDayID = nil }
    }

    private func startsWeek(_ date: Date) -> Bool {
        calendar.component(.weekday, from: date) == calendar.firstWeekday
    }

    private func description(_ day: PomodoroStatistics.Day) -> String {
        let date = day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(date): \(PomodoroStatistics.duration(day.focus)), \(day.sessions) session\(day.sessions == 1 ? "" : "s")"
    }
}

struct PomodoroHistoryBar: View {
    let focus: TimeInterval
    let peak: TimeInterval
    let isToday: Bool
    let isHovered: Bool
    @NotchIncreasedContrast private var increasedContrast

    var body: some View {
        // Match the whole minutes shown in the peek. Sub-minute activity still reads as 0m.
        let hasFocusMinutes = focus >= 60
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(hasFocusMinutes ? PomodoroStyle.focus.opacity(isToday ? 1 : 0.85) : .white.opacity(0.10))
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(.white.opacity(increasedContrast ? 1 : 0.65), lineWidth: 1)
                        .shadow(color: hasFocusMinutes ? PomodoroStyle.focus.opacity(0.55) : .white.opacity(0.20), radius: 3)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: hasFocusMinutes ? max(5, 92 * focus / max(peak, 3600)) : 4)
    }
}

struct PomodoroHistoryPeek: View {
    let day: PomodoroStatistics.Day
    let calendar: Calendar

    var body: some View {
        VStack(spacing: 3) {
            Text(day.date.formatted(dateFormat))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
            Text("\(PomodoroStatistics.duration(day.focus)) Focus")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 128, height: 44)
        .background(Color(white: 0.16), in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var dateFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.month(.wide).day()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        return format
    }
}
