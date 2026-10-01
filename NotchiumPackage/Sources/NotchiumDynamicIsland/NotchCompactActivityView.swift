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
        // Retained content exists only while geometry is still retracting it. Once the shell is
        // back at rest (reveal 0) it is gone, whether or not the spring's removal callback has
        // arrived yet, so nothing stale can linger beside the restored activity.
        // A banner replacing the compact activity (Calendar over a transfer) takes the row at once:
        // retained content only accompanies a retraction back to rest.
        let shown = current ?? (retracting && Self.retainsContent(reveal: reveal, restoresMedia: model.showsCollapsedMedia)
                                && model.presentedNotification == nil ? retained : nil)
        ZStack {
            if let shown, let activity = shown.content.compactActivity {
                NotchCompactActivityView(activity: activity,
                                         geometry: NotchCompactGeometry(layout: layout, activity: activity),
                                         reveal: reveal,
                                         entryID: shown.id, reduceMotion: model.reduceMotion,
                                         action: model.activateCurrentActivity,
                                         blendsMedia: activity.blendsWithMedia && model.mediaVisiblyPlaying)
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

    static func retainsContent(reveal: CGFloat, restoresMedia: Bool) -> Bool {
        // Music's leading artwork begins to emerge below one third of the reveal.
        // The outgoing glyph must have yielded that slot by then.
        reveal > (restoresMedia ? 1 / 3 : 0.001)
    }
}

struct NotchCompactActivityView: View {
    let activity: NotchCompactActivity
    let geometry: NotchCompactGeometry
    let reveal: CGFloat
    let entryID: UUID
    let reduceMotion: Bool
    let action: @MainActor () -> Void
    var inlineWidth: CGFloat? = nil
    /// Music is visibly playing: artwork and countdown lead, the waveform trails.
    var blendsMedia = false
    @Environment(\.notchMediaRenderer) private var mediaRenderer

    private var progress: CGFloat { min(max(reveal, 0), 1) }
    /// Content slides out from beneath the physical notch just behind the growing edge, so the
    /// outer glyph leads and the text follows; exit slides it back under. No separate animation.
    private var inset: CGFloat { reduceMotion ? 0 : (1 - progress) * geometry.sideWidth * 0.8 }
    /// Text is uncovered by the shell mask first, then settles in through movement.
    private var textOpacity: Double { Double(min(max((progress - 0.3) / 0.55, 0), 1)) }

    var body: some View {
        Group {
            if let inlineWidth {
                HStack(spacing: 0) {
                    leading.frame(width: inlineWidth * 0.52, alignment: .leading)
                    trailing.frame(width: inlineWidth * 0.48, alignment: .trailing)
                }
                .frame(width: inlineWidth, height: geometry.height)
            } else {
                Button(action: action) { compactRow }
                    .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("notchium.compact.activity")
    }

    private var compactRow: some View {
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

    @ViewBuilder private var leading: some View {
        if blendsMedia, case let .countdown(countdown) = activity.trailing, let mediaRenderer {
            HStack(spacing: 7) {
                mediaRenderer.mediaArtwork(size: 20)
                    .frame(width: 20, height: 20)
                    .clipShape(.rect(cornerRadius: 5, style: .continuous))
                    .scaleEffect(reduceMotion ? 1 : 0.7 + 0.3 * progress)
                NotchCountdownText(countdown: countdown, font: .system(size: 12, weight: .semibold).monospacedDigit())
                    .opacity(textOpacity)
            }
            .padding(.leading, 12)
        } else if activity.showsTitle {
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
        case let .thumbnail(url):
            // The capture itself emerges from the notch: it rides the shell's reveal, no extra timer.
            NotchThumbnailView(url: url, size: CGSize(width: 30, height: 20), cornerRadius: 4)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
                .scaleEffect(reduceMotion ? 1 : 0.55 + 0.45 * progress, anchor: .trailing)
        case let .device(style, connected):
            NotchDeviceTurnGlyph(style: style, connected: connected, trigger: entryID, reduceMotion: reduceMotion)
                .foregroundStyle(tint)
                .scaleEffect(reduceMotion ? 1 : 0.7 + 0.3 * progress)
        }
    }

    @ViewBuilder private var trailing: some View {
        if blendsMedia, let mediaRenderer {
            mediaRenderer.mediaWaveform()
                .opacity(textOpacity)
                .padding(.trailing, 14)
        } else {
            standardTrailing
        }
    }

    @ViewBuilder private var standardTrailing: some View {
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
            case let .progress(fraction, label):
                // Only the progress itself moves while active; updates glide, never re-enter.
                HStack(spacing: 7) {
                    if let fraction {
                        NotchCompactLevelBar(level: fraction, reveal: progress, dimmed: false)
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(.numericText())
                        .opacity(textOpacity)
                }
                .animation(reduceMotion ? nil : NotchMotion.compactLevel, value: label)
            case let .countdown(countdown):
                NotchCountdownTimeline(countdown: countdown) { date in
                    HStack(spacing: 7) {
                        NotchCompactLevelBar(level: countdown.elapsedFraction(at: date), reveal: progress,
                                             dimmed: !countdown.isRunning)
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)
                        Text(NotchCountdown.label(countdown.remaining(at: date)))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize()
                            .opacity(textOpacity * (countdown.isRunning ? 1 : 0.6))
                    }
                }
            }
        }
        // A state morph (progress → Done) cross-fades in place inside the unchanged shell.
        .animation(reduceMotion ? nil : NotchMotion.compactSwap, value: trailingKind)
        .padding(.trailing, activity.showsTitle ? 14 : 13)
        .padding(.leading, 6)
    }

    private var tint: Color { activity.tint.color }

    private var trailingKind: Int {
        switch activity.trailing {
        case .level: 0
        case .text: 1
        case .battery: 2
        case .progress: 3
        case .countdown: 4
        }
    }

    private var accessibilityValue: String {
        switch activity.trailing {
        case let .level(level): "\(Self.percent(level)) percent"
        case let .text(text): text
        case let .battery(level, charging): "\(Self.percent(level)) percent\(charging ? ", charging" : "")"
        case let .progress(fraction, label): fraction.map { "\(Self.percent($0)) percent" } ?? label
        case let .countdown(countdown):
            NotchCountdown.spokenLabel(countdown.remaining(at: .now)) + (countdown.isRunning ? "" : ", paused")
        }
    }

    private static func percent(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 100).rounded()) }
}

extension NotchCompactActivity.Tint {
    var color: Color {
        switch self {
        case .primary: .white
        case .muted: .white.opacity(0.62)
        case .charging: Color(red: 0.19, green: 0.82, blue: 0.35)
        case .warning: Color(red: 1, green: 0.27, blue: 0.23)
        // macOS Focus's indigo, softened for the black shell.
        case .focus: Color(red: 0.49, green: 0.47, blue: 1.0)
        }
    }
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
    let connected: Bool
    let trigger: UUID
    let reduceMotion: Bool
    @State private var turnStart: Date?

    init(style: NotchDeviceStyle, connected: Bool, trigger: UUID, reduceMotion: Bool) {
        self.style = style
        self.connected = connected
        self.trigger = trigger
        self.reduceMotion = reduceMotion
        // Start turned away on the very first frame; the turn never pops from rest.
        _turnStart = State(initialValue: Self.turns(style, connected, reduceMotion) ? .now : nil)
    }

    private static func turns(_ style: NotchDeviceStyle, _ connected: Bool, _ reduceMotion: Bool) -> Bool {
        connected && style.spinsOnConnect && !reduceMotion
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
        // A coalesced update keeps this view: a reconnect or a different wearable turns again,
        // a disconnect settles immediately. One activity, never a pile-up of entries.
        .onChange(of: TurnKey(style: style, connected: connected)) { _, _ in
            turnStart = Self.turns(style, connected, reduceMotion) ? .now : nil
        }
        .task(id: TurnTask(trigger: trigger, start: turnStart)) {
            guard turnStart != nil else { return }
            try? await Task.sleep(for: .seconds(NotchMotion.deviceTurn))
            guard !Task.isCancelled else { return }
            turnStart = nil
        }
    }

    private struct TurnKey: Equatable { let style: NotchDeviceStyle; let connected: Bool }
    private struct TurnTask: Equatable { let trigger: UUID; let start: Date? }
}

/// Re-renders once per second only while the countdown runs; a paused countdown is static.
/// Ticks are aligned to the deadline so the displayed second changes exactly on time.
public struct NotchCountdownTimeline<Content: View>: View {
    let countdown: NotchCountdown
    let content: (Date) -> Content

    public init(countdown: NotchCountdown, @ViewBuilder content: @escaping (Date) -> Content) {
        self.countdown = countdown
        self.content = content
    }

    public var body: some View {
        if let endsAt = countdown.endsAt {
            let phase = endsAt.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            let anchor = Date(timeIntervalSinceReferenceDate: Date.now.timeIntervalSinceReferenceDate.rounded(.down) - 1 + phase)
            TimelineView(.periodic(from: anchor, by: 1)) { context in content(context.date) }
        } else {
            content(.now)
        }
    }
}

/// The remaining time as text, ticking from the deadline.
public struct NotchCountdownText: View {
    let countdown: NotchCountdown
    let font: Font

    public init(countdown: NotchCountdown, font: Font) {
        self.countdown = countdown
        self.font = font
    }

    public var body: some View {
        NotchCountdownTimeline(countdown: countdown) { date in
            Text(NotchCountdown.label(countdown.remaining(at: date)))
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(NotchCountdown.spokenLabel(countdown.remaining(at: date)))
        }
    }
}
