import SwiftUI

/// Dynamic-Island compact content: a glyph and short title beside the notch's leading edge,
/// a value on its trailing edge. The black shell never grows downward for these.
public struct NotchCompactActivity: Equatable, Sendable {
    public enum Glyph: Equatable, Sendable {
        case symbol(String, variableValue: Double? = nil)
        /// Output devices turn into place on entry; the same motion serves every device style.
        /// `connected: false` (a disconnect) settles without the turn.
        case device(NotchDeviceStyle, connected: Bool = true)
        /// A downsampled file preview (a screenshot) that slides out from beneath the notch.
        case thumbnail(URL)
    }

    public enum Trailing: Equatable, Sendable {
        case level(Double)
        case text(String)
        case battery(level: Double, charging: Bool)
        /// A thin bar plus a short label ("72%", "72% +2"); nil fraction shows the label alone.
        case progress(Double?, label: String)
        /// Remaining time toward a deadline, drawn from the deadline itself.
        case countdown(NotchCountdown)
    }

    public enum Tint: Equatable, Sendable { case primary, muted, charging, warning, focus }

    public let glyph: Glyph
    /// Always spoken; shown beside the glyph only when `showsTitle`.
    public let title: String
    public let showsTitle: Bool
    public let trailing: Trailing
    public let tint: Tint
    /// While Music is visibly playing, the leading side shows its artwork beside the countdown and
    /// the trailing side keeps its waveform: one activity that still reads as Music.
    public let blendsWithMedia: Bool

    public init(glyph: Glyph, title: String, showsTitle: Bool = true, trailing: Trailing, tint: Tint = .primary,
                blendsWithMedia: Bool = false) {
        self.glyph = glyph
        self.title = title
        self.showsTitle = showsTitle
        self.trailing = trailing
        self.tint = tint
        self.blendsWithMedia = blendsWithMedia
    }

    /// Symmetric sides sized to the content, so the notch stays centred and an untitled
    /// activity is not surrounded by empty black. Long status text ("Disconnected") gets full width.
    var sideWidth: CGFloat {
        if showsTitle { return NotchCompactGeometry.sideWidth }
        switch trailing {
        case let .text(text) where text.count > 9: return NotchCompactGeometry.sideWidth
        case .progress, .countdown: return NotchCompactGeometry.sideWidth
        default: return 86
        }
    }

    public init(_ hud: NotchAudioHUD) {
        switch hud.kind {
        case .outputChanged:
            // Device glyph beside the notch, no name. Opposite: a trustworthy aggregate battery
            // when the source reports one, otherwise "Connected".
            self.init(glyph: .device(hud.deviceStyle), title: Self.shortName(hud.deviceName),
                      showsTitle: false,
                      trailing: hud.battery.map { .battery(level: $0.level, charging: $0.isCharging) }
                        ?? .text("Connected"))
        case .deviceDisconnected:
            self.init(glyph: .device(hud.deviceStyle, connected: false), title: Self.shortName(hud.deviceName),
                      showsTitle: false, trailing: .text("Disconnected"), tint: .muted)
        case .volume where hud.isMuted:
            // The preserved level stays visible, dimmed, so unmuting animates back from it.
            self.init(glyph: .symbol("speaker.slash.fill"), title: "Muted",
                      trailing: .level(min(max(hud.volume ?? 0, 0), 1)), tint: .muted)
        case .volume:
            let level = min(max(hud.volume ?? 0, 0), 1)
            self.init(glyph: .symbol("speaker.wave.3.fill", variableValue: level), title: "Volume",
                      trailing: hud.volume == nil ? .text("Unavailable") : .level(level))
        }
    }

    /// "Marcus’s AirPods Pro" → "AirPods Pro": the owner prefix does not fit beside the notch.
    static func shortName(_ name: String) -> String {
        for separator in ["’s ", "'s "] {
            if let range = name.range(of: separator), range.upperBound < name.endIndex {
                return String(name[range.upperBound...])
            }
        }
        return name
    }

    public static func charging(level: Double) -> Self {
        .init(glyph: .symbol("bolt.fill"), title: "Charging",
              trailing: .battery(level: level, charging: true), tint: .charging)
    }

    public static func lowBattery(level: Double) -> Self {
        .init(glyph: .symbol("exclamationmark.circle.fill"), title: "Low Battery",
              trailing: .battery(level: level, charging: false), tint: .warning)
    }

    /// The same language as Low Battery with a stronger glyph: restrained, not alarming.
    public static func criticalBattery(level: Double) -> Self {
        .init(glyph: .symbol("exclamationmark.triangle.fill"), title: "Critical",
              trailing: .battery(level: level, charging: false), tint: .warning)
    }

    public static func powerDisconnected(level: Double) -> Self {
        .init(glyph: .symbol("bolt.slash.fill"), title: "On Battery",
              trailing: .battery(level: level, charging: false), tint: .muted)
    }
}

/// A deadline-based countdown. The visible time is derived from the deadline at render time,
/// so the activity is submitted only when its phase or pause state changes.
public struct NotchCountdown: Equatable, Sendable {
    public let total: TimeInterval
    /// The absolute end while running; nil while paused.
    public let endsAt: Date?
    /// The frozen remaining time while paused.
    public let pausedRemaining: TimeInterval

    public static func running(total: TimeInterval, endsAt: Date) -> Self {
        Self(total: total, endsAt: endsAt, pausedRemaining: 0)
    }

    public static func paused(total: TimeInterval, remaining: TimeInterval) -> Self {
        Self(total: total, endsAt: nil, pausedRemaining: remaining)
    }

    public var isRunning: Bool { endsAt != nil }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, endsAt.map { $0.timeIntervalSince(now) } ?? pausedRemaining)
    }

    /// Elapsed share of the phase, 0…1.
    public func elapsedFraction(at now: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(max(1 - remaining(at: now) / total, 0), 1)
    }

    /// "24:18", or "1:02:03" past an hour. Rounds up so 00:00 appears only at the end.
    public static func label(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        let (hours, minutes, secs) = (whole / 3600, whole % 3600 / 60, whole % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
    }

    /// "24 minutes, 18 seconds remaining" for VoiceOver.
    public static func spokenLabel(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = whole >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .full
        return (formatter.string(from: TimeInterval(whole)) ?? "") + " remaining"
    }
}

public enum NotchDeviceStyle: String, Equatable, Sendable {
    case airPods, airPodsPro, airPodsMax, beats, headphones, speaker, display, airPlay, builtIn

    public var symbol: String {
        switch self {
        case .airPods: "airpods"
        case .airPodsPro: "airpodspro"
        case .airPodsMax: "airpodsmax"
        case .beats: "beats.headphones"
        case .headphones: "headphones"
        case .speaker: "hifispeaker.fill"
        case .display: "display"
        case .airPlay: "airplayaudio"
        case .builtIn: "laptopcomputer"
        }
    }

    /// Wearables turn into place; fixed outputs settle with the ordinary glyph motion.
    public var spinsOnConnect: Bool {
        switch self {
        case .airPods, .airPodsPro, .airPodsMax, .beats, .headphones: true
        default: false
        }
    }

    /// Classifies from Core Audio's public name and transport; unknown devices stay generic.
    public static func classify(name: String, transport: NotchAudioTransport) -> Self {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return .airPodsMax }
        if lowered.contains("airpods pro") { return .airPodsPro }
        if lowered.contains("airpods") { return .airPods }
        if lowered.contains("beats") { return .beats }
        switch transport {
        case .builtIn: return .builtIn
        case .airPlay: return .airPlay
        case .display: return .display
        case .bluetooth: return lowered.contains("speaker") ? .speaker : .headphones
        case .usb, .other: return lowered.contains("headphone") || lowered.contains("headset") ? .headphones : .speaker
        }
    }
}

public enum NotchAudioTransport: String, Equatable, Sendable {
    case builtIn, bluetooth, usb, display, airPlay, other
}

/// Leading side + physical notch + trailing side, at exactly the collapsed height.
struct NotchCompactGeometry: Equatable {
    static let sideWidth: CGFloat = 106
    static let shoulderRadius: CGFloat = 6
    let hardwareWidth: CGFloat
    let height: CGFloat
    let sideWidth: CGFloat

    init(layout: NotchPanelLayout, activity: NotchCompactActivity? = nil) {
        hardwareWidth = layout.hardwareNotchGeometry?.frame.width ?? layout.collapsedVisibleFrame.width
        height = layout.collapsedVisibleFrame.height
        sideWidth = activity?.sideWidth ?? Self.sideWidth
    }

    /// Shoulders flare outside the body so the sides keep their full content width.
    var width: CGFloat { hardwareWidth + sideWidth * 2 + Self.shoulderRadius * 2 }
    var bodyWidth: CGFloat { hardwareWidth + sideWidth * 2 }
    var bottomRadius: CGFloat { min(13, height * 0.4) }
}

extension NotchMotion {
    /// Fast response, soft settle, ~1% overshoot: the sides grow out of the notch.
    static let compactIn = Animation.interactiveSpring(response: 0.36, dampingFraction: 0.86, blendDuration: 0)
    /// The inverse, critically damped: the sides retract into the notch without undershoot.
    static let compactOut = Animation.interactiveSpring(response: 0.30, dampingFraction: 1.0, blendDuration: 0)
    /// Replacing one compact activity with another inside an unchanged shell.
    static let compactSwap = Animation.smooth(duration: 0.22)
    /// Continuous values (volume) follow input without restarting entry.
    static let compactLevel = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.92, blendDuration: 0)
    static let deviceTurn: TimeInterval = 0.8
}
