import SwiftUI

/// Hosts the compact activity in the shell's top row. Its content keeps rendering while the
/// shell retracts, so it is clipped back into the notch instead of vanishing first.
struct NotchCompactActivitySlot: View {
    let model: DynamicIslandPresentationModel
    let layout: NotchPanelLayout
    @Environment(\.notchCompactReveal) private var reveal
    @Environment(\.notchCompactRetracting) private var retracting
    @State private var retained: NotchNotification?

    private var current: NotchNotification? {
        guard let notification = model.presentedNotification,
              notification.presentationStyle == .compact else { return nil }
        return notification
    }

    var body: some View {
        let shown = current ?? (retracting ? retained : nil)
        ZStack {
            if let shown, let activity = shown.content.compactActivity {
                NotchCompactActivityView(activity: activity,
                                         geometry: NotchCompactGeometry(layout: layout, activity: activity),
                                         reveal: reveal,
                                         entryID: shown.id, reduceMotion: model.reduceMotion,
                                         action: model.activateCurrentActivity)
                    // A coalesced update keeps its ID: the same view updates in place.
                    .id(shown.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                            removal: .opacity))
                    .allowsHitTesting(current != nil)
            }
        }
        .animation(NotchMotion.compactSwap, value: shown?.id)
        .onChange(of: current, initial: true) { _, value in
            if let value { retained = value }
        }
    }
}

struct NotchCompactActivityView: View {
    let activity: NotchCompactActivity
    let geometry: NotchCompactGeometry
    let reveal: CGFloat
    let entryID: UUID
    let reduceMotion: Bool
    let action: @MainActor () -> Void

    private var progress: CGFloat { min(max(reveal, 0), 1) }
    /// Content slides out from beneath the physical notch just behind the growing edge, so the
    /// outer glyph leads and the text follows; exit slides it back under. No separate animation.
    private var inset: CGFloat { reduceMotion ? 0 : (1 - progress) * geometry.sideWidth * 0.8 }
    /// Text is uncovered by the shell mask first, then settles in through movement.
    private var textOpacity: Double { Double(min(max((progress - 0.3) / 0.55, 0), 1)) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                leading
                    .offset(x: inset)
                    .frame(width: geometry.sideWidth, alignment: .leading)
                Color.clear.frame(width: geometry.hardwareWidth)
                trailing
                    .offset(x: -inset)
                    .frame(width: geometry.sideWidth, alignment: .trailing)
            }
            .frame(width: geometry.bodyWidth, height: geometry.height)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("notchium.compact.activity")
    }

    @ViewBuilder private var leading: some View {
        if activity.showsTitle {
            HStack(spacing: 6) {
                glyph
                    .frame(width: 18, height: 18)
                Text(activity.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .opacity(textOpacity)
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
        } else {
            glyph
                .frame(width: 20, height: 20)
                .padding(.leading, 13)
        }
    }

    @ViewBuilder private var glyph: some View {
        switch activity.glyph {
        case let .symbol(name, variableValue):
            Image(systemName: name, variableValue: variableValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(reduceMotion ? 1 : 0.62 + 0.38 * progress)
                .rotationEffect(.degrees(reduceMotion ? 0 : -16 * (1 - progress)))
        case let .device(style):
            NotchDeviceTurnGlyph(style: style, trigger: entryID, reduceMotion: reduceMotion)
                .scaleEffect(reduceMotion ? 1 : 0.7 + 0.3 * progress)
        }
    }

    @ViewBuilder private var trailing: some View {
        Group {
            switch activity.trailing {
            case let .level(level):
                // Spans the trailing side from just past the physical notch to the outer padding.
                NotchCompactLevelBar(level: level, reveal: progress, dimmed: activity.tint == .muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
            case let .text(text):
                // Native secondary status: quiet, regular weight, never an accent colour.
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .opacity(textOpacity)
            case let .battery(level, charging):
                HStack(spacing: 6) {
                    Text("\(Self.percent(level))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .opacity(textOpacity)
                    NotchBatteryGlyph(level: level * Double(progress), tint: tint, charging: charging)
                }
            }
        }
        .padding(.trailing, activity.showsTitle ? 14 : 13)
        .padding(.leading, 6)
    }

    private var tint: Color {
        switch activity.tint {
        case .primary: .white
        case .muted: .white.opacity(0.62)
        case .charging: Color(red: 0.19, green: 0.82, blue: 0.35)
        case .warning: Color(red: 1, green: 0.27, blue: 0.23)
        }
    }

    private var accessibilityValue: String {
        switch activity.trailing {
        case let .level(level): "\(Self.percent(level)) percent"
        case let .text(text): text
        case let .battery(level, charging): "\(Self.percent(level)) percent\(charging ? ", charging" : "")"
        }
    }

    private static func percent(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 100).rounded()) }
}

/// Entry fills from empty with the reveal; later values glide from wherever the bar is.
private struct NotchCompactLevelBar: View {
    let level: Double
    let reveal: CGFloat
    let dimmed: Bool

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white.opacity(dimmed ? 0.4 : 1))
                        .animation(NotchMotion.compactLevel, value: dimmed)
                        .frame(width: proxy.size.width * CGFloat(min(max(level, 0), 1)) * reveal)
                        .animation(NotchMotion.compactLevel, value: level)
                }
        }
    }
}

private struct NotchBatteryGlyph: View {
    let level: Double
    let tint: Color
    let charging: Bool

    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(tint)
                            .frame(width: max(0, (proxy.size.width - 4) * CGFloat(min(max(level, 0), 1))))
                            .padding(2)
                    }
                }
                .frame(width: 23, height: 11)
            Capsule().fill(.white.opacity(0.4)).frame(width: 1.5, height: 4)
        }
        .accessibilityHidden(true)
    }
}

/// One controlled half turn with a soft ease-out, then still. The timeline runs only for the
/// turn itself; no display link remains active while the activity is idle.
private struct NotchDeviceTurnGlyph: View {
    let style: NotchDeviceStyle
    let trigger: UUID
    let reduceMotion: Bool
    @State private var turnStart: Date?

    init(style: NotchDeviceStyle, trigger: UUID, reduceMotion: Bool) {
        self.style = style
        self.trigger = trigger
        self.reduceMotion = reduceMotion
        // Start turned away on the very first frame; the turn never pops from rest.
        _turnStart = State(initialValue: style.spinsOnConnect && !reduceMotion ? .now : nil)
    }

    var body: some View {
        TimelineView(.animation(paused: turnStart == nil)) { context in
            let t = turnStart.map { min(1, context.date.timeIntervalSince($0) / NotchMotion.deviceTurn) } ?? 1
            let eased = 1 - pow(1 - t, 3)
            Image(systemName: style.symbol)
                .font(.system(size: 14, weight: .medium))
                .rotation3DEffect(.degrees(-180 * (1 - eased)), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .rotationEffect(.degrees(8 * (1 - eased)))
        }
        .task(id: trigger) {
            guard turnStart != nil else { return }
            try? await Task.sleep(for: .seconds(NotchMotion.deviceTurn))
            turnStart = nil
        }
    }
}
