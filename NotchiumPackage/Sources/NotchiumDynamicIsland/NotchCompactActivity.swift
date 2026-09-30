import SwiftUI

/// Dynamic-Island compact content: a glyph and short title beside the notch's leading edge,
/// a value on its trailing edge. The black shell never grows downward for these.
public struct NotchCompactActivity: Equatable, Sendable {
    public enum Glyph: Equatable, Sendable {
        case symbol(String, variableValue: Double? = nil)
        /// Output devices turn into place on entry; the same motion serves every device style.
        case device(NotchDeviceStyle)
    }

    public enum Trailing: Equatable, Sendable {
        case level(Double)
        case text(String)
        case battery(level: Double, charging: Bool)
    }

    public enum Tint: Equatable, Sendable { case primary, muted, charging, warning }

    public let glyph: Glyph
    /// Always spoken; shown beside the glyph only when `showsTitle`.
    public let title: String
    public let showsTitle: Bool
    public let trailing: Trailing
    public let tint: Tint

    public init(glyph: Glyph, title: String, showsTitle: Bool = true, trailing: Trailing, tint: Tint = .primary) {
        self.glyph = glyph
        self.title = title
        self.showsTitle = showsTitle
        self.trailing = trailing
        self.tint = tint
    }

    /// Symmetric sides sized to the content, so the notch stays centred and an untitled
    /// activity is not surrounded by empty black.
    var sideWidth: CGFloat { showsTitle ? NotchCompactGeometry.sideWidth : 86 }

    public init(_ hud: NotchAudioHUD) {
        switch hud.kind {
        case .outputChanged:
            // Every output change: device glyph beside the notch, "Connected" opposite, no name.
            self.init(glyph: .device(hud.deviceStyle), title: Self.shortName(hud.deviceName),
                      showsTitle: false, trailing: .text("Connected"))
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
