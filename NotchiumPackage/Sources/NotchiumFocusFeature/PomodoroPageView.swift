import NotchiumDesignSystem
import NotchiumDynamicIsland
import SwiftUI

/// The timer leads; today's numbers sit quietly beside it. History is one click away.
struct PomodoroPageView: View {
    let model: PomodoroModel
    @State private var showsHistory = false
    @Environment(\.notchPomodoroPageVisible) private var isVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if showsHistory {
                PomodoroHistoryView(model: model) { showsHistory = false }
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 6)))
            } else {
                timerPage
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -6)))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.24), value: showsHistory)
        .padding(.horizontal, ExpandedPageStyle.outerInset)
        .padding(.top, ExpandedPageStyle.topInset)
        .padding(.bottom, ExpandedPageStyle.bottomInset)
        .foregroundStyle(.white)
    }

    private var timerPage: some View {
        HStack(alignment: .center, spacing: ExpandedPageStyle.columnGap) {
            PomodoroTimerColumn(model: model, isVisible: isVisible)
                .frame(maxWidth: .infinity)
            PomodoroTodayColumn(model: model, isVisible: isVisible) { showsHistory = true }
                .frame(width: 150)
        }
    }
}

/// Color only on key information: the phase chip, progress, the primary control, cycle dots and
/// the Today/Streak glyphs. Warm for Focus, fresh mint for a short break, calm blue for the long one.
enum PomodoroStyle {
    static let focus = Color(red: 1.0, green: 0.52, blue: 0.40)
    static let shortBreak = Color(red: 0.42, green: 0.86, blue: 0.66)
    static let longBreak = Color(red: 0.46, green: 0.70, blue: 1.0)
    static let streak = Color(red: 1.0, green: 0.66, blue: 0.30)

    static func accent(_ phase: PomodoroPhase) -> Color {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }

    static func symbol(_ phase: PomodoroPhase) -> String {
        switch phase {
        case .focus: "timer"
        case .shortBreak: "leaf.fill"
        case .longBreak: "beach.umbrella.fill"
        }
    }

    /// Friendly, bubbly, still native: the system rounded design with tabular digits.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

private struct PomodoroTimerColumn: View {
    let model: PomodoroModel
    let isVisible: Bool

    var body: some View {
        let state = model.state
        let countdown = model.countdown()
        let accent = PomodoroStyle.accent(state.phase)
        VStack(spacing: 8) {
            phaseChip(state, accent: accent)
            // Ticks only while the page is on screen; the deadline is the truth either way.
            Group {
                if isVisible {
                    NotchCountdownTimeline(countdown: countdown) { date in face(countdown, accent: accent, at: date) }
                } else {
                    face(countdown, accent: accent, at: .now)
                }
            }
            PomodoroControlsView(model: model,
                                 centersPrimary: state.phase == .focus && state.controls.contains(.resume))
            cycleDots(state)
        }
        .animation(.smooth(duration: 0.3), value: state.phase)
    }

    private func phaseChip(_ state: PomodoroState, accent: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: PomodoroStyle.symbol(state.phase)).font(.system(size: 9, weight: .bold))
            Text(state.phase.title.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.1)
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 9)
        .frame(height: 20)
        .background(accent.opacity(0.16), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func face(_ countdown: NotchCountdown, accent: Color, at date: Date) -> some View {
        let remaining = countdown.remaining(at: date)
        let paused = model.state.isActive && !countdown.isRunning
        return VStack(spacing: 9) {
            Text(NotchCountdown.label(remaining))
                .font(PomodoroStyle.rounded(48, .semibold))
                .foregroundStyle(.white.opacity(paused ? 0.5 : 1))
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel(NotchCountdown.spokenLabel(remaining))
                .accessibilityValue(countdown.isRunning ? "" : (model.state.isActive ? "Paused" : "Ready"))
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent.opacity(paused ? 0.5 : 1))
                            .frame(width: max(6, proxy.size.width * countdown.elapsedFraction(at: date)))
                    }
            }
            .frame(width: 176, height: 6)
            .accessibilityHidden(true)
        }
    }

    /// One dot per configured session: taken sessions filled, the current one ringed.
    private func cycleDots(_ state: PomodoroState) -> some View {
        let total = model.configuration.sessionsPerCycle
        let current = model.focusNumber
        return HStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(1...total, id: \.self) { index in
                    Circle()
                        .fill(index < current || (index == current && state.phase.isBreak)
                              ? PomodoroStyle.focus : .white.opacity(0.14))
                        .overlay {
                            if index == current, state.phase == .focus {
                                Circle().strokeBorder(PomodoroStyle.focus, lineWidth: 1.5)
                            }
                        }
                        .frame(width: 7, height: 7)
                }
            }
            Text("\(current) of \(total)")
                .font(PomodoroStyle.rounded(10, .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus session \(current) of \(total)")
    }
}

/// Today and Streak stay in view: a quiet grouped panel, tinted glyphs, rounded values.
private struct PomodoroTodayColumn: View {
    let model: PomodoroModel
    let isVisible: Bool
    let showHistory: () -> Void

    var body: some View {
        // Today includes the running session; a minute-level refresh is plenty for "1h 32m".
        TimelineView(.periodic(from: .now, by: isVisible && model.state.isActive ? 30 : 3600)) { context in
            let stats = model.statistics(at: context.date)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 9) {
                    row("clock.fill", PomodoroStyle.focus, "Today", PomodoroStatistics.duration(stats.todayFocus))
                    row("checkmark.circle.fill", PomodoroStyle.shortBreak, "Sessions", "\(stats.todaySessions)")
                    row("flame.fill", stats.streak > 0 ? PomodoroStyle.streak : .white.opacity(0.3), "Streak",
                        stats.streak == 0 ? "—" : "\(stats.streak) day\(stats.streak == 1 ? "" : "s")")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 14, style: .continuous))
                Button(action: showHistory) {
                    HStack(spacing: 4) {
                        Text("History")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.leading, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows focus time for the past 30 days and lifetime totals")
                .accessibilityIdentifier("notchium.pomodoro.history")
            }
        }
    }

    private func row(_ symbol: String, _ tint: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 4)
            Text(value)
                .font(PomodoroStyle.rounded(13, .semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

/// The past 30 days as quiet bars, grouped by week, with lifetime totals above.
struct PomodoroHistoryView: View {
    let model: PomodoroModel
    let close: () -> Void

    var body: some View {
        let stats = model.statistics()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Button(action: close) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        Text("Past 30 Days")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to timer")
                .accessibilityIdentifier("notchium.pomodoro.history.back")
                Spacer()
                total("Sessions", "\(stats.totalSessions)")
                total("Focus", PomodoroStatistics.duration(stats.totalFocus))
            }
            PomodoroMonthBars(days: stats.days, calendar: model.calendar)
        }
    }

    private func total(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(PomodoroStyle.rounded(13, .semibold))
            Text(title).font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total \(title): \(value)")
    }
}

private struct PomodoroMonthBars: View {
    let days: [PomodoroStatistics.Day]
    let calendar: Calendar

    var body: some View {
        let peak = max(days.map(\.focus).max() ?? 0, 3600)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let isToday = index == days.count - 1
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(day.focus > 0 ? PomodoroStyle.focus.opacity(isToday ? 1 : 0.85) : .white.opacity(0.10))
                            .frame(height: day.focus > 0 ? max(5, 92 * day.focus / peak) : 4)
                    }
                    .frame(width: 9)
                    .padding(.leading, index == 0 ? 0 : (startsWeek(day.date) ? 7 : 3.5))
                    .help(description(day))
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
    }

    private func startsWeek(_ date: Date) -> Bool {
        calendar.component(.weekday, from: date) == calendar.firstWeekday
    }

    private func description(_ day: PomodoroStatistics.Day) -> String {
        let date = day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        guard day.focus > 0 else { return "\(date): no focus" }
        return "\(date): \(PomodoroStatistics.duration(day.focus)), \(day.sessions) session\(day.sessions == 1 ? "" : "s")"
    }
}
