import ImageIO
import SwiftUI

/// Original, locally rendered product artwork. Frames are evenly spaced in angle; SwiftUI
/// supplies the timing. The first and last frame share a pose, so a new turn starts cleanly.
enum NotchAirPodsArtwork: String, CaseIterable, Sendable {
    case airPods = "AirPodsTurn"
    case airPodsPro = "AirPodsProTurn"
    case airPodsMax = "AirPodsMaxTurn"

    static let frameCount = 61
    static let framePixels = 96

    init?(style: NotchDeviceStyle) {
        switch style {
        case .airPods: self = .airPods
        case .airPodsPro: self = .airPodsPro
        case .airPodsMax: self = .airPodsMax
        default: return nil
        }
    }

    var resourceURL: URL? { Bundle.module.url(forResource: rawValue, withExtension: "png") }

    static func frame(at progress: Double) -> Int {
        let clamped = progress.isFinite ? min(max(progress, 0), 1) : 1
        return Int((clamped * Double(frameCount - 1)).rounded())
    }

    @MainActor func image(at progress: Double) -> CGImage? {
        let frames: [CGImage]
        switch self {
        case .airPods: frames = Self.airPodsFrames
        case .airPodsPro: frames = Self.proFrames
        case .airPodsMax: frames = Self.maxFrames
        }
        guard frames.count == Self.frameCount else { return nil }
        return frames[Self.frame(at: progress)]
    }

    // Immutable crops share one decoded sheet per model. Only the requested model loads, once;
    // later animation frames just choose a prepared image, without file I/O or decoding.
    @MainActor private static let airPodsFrames = airPods.loadFrames()
    @MainActor private static let proFrames = airPodsPro.loadFrames()
    @MainActor private static let maxFrames = airPodsMax.loadFrames()

    private func loadFrames() -> [CGImage] {
        guard let url = resourceURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              sheet.width == Self.framePixels * Self.frameCount,
              sheet.height == Self.framePixels else { return [] }
        return (0..<Self.frameCount).compactMap { index in
            sheet.cropping(to: CGRect(x: index * Self.framePixels, y: 0,
                                     width: Self.framePixels, height: Self.framePixels))
        }
    }
}

enum NotchAirPodsMotion {
    /// Keep yaw unwrapped across events, so reversing an interrupted turn starts at the
    /// current orientation. Either direction finishes on a whole turn: the front pose.
    static func destination(from phase: Double, connected: Bool) -> Double {
        let phase = canonical(phase)
        return connected ? phase.rounded(.down) + 1 : phase.rounded(.up) - 1
    }

    static func pose(at phase: Double) -> Double {
        let phase = canonical(phase)
        return phase - phase.rounded(.down)
    }

    private static func canonical(_ phase: Double) -> Double {
        guard phase.isFinite else { return 0 }
        let nearest = phase.rounded()
        // Cubic interpolation can finish a fraction of an ulp off its endpoint. Preserve
        // a full next turn instead of mistaking that rounding residue for an interruption.
        return abs(phase - nearest) < 1e-9 ? nearest : phase
    }

    /// Connect turns forward; disconnect turns back. Native keyframes supply the live phase
    /// and preserve its velocity on interruption. There is no reset to a different pose.
    static func turn(from phase: Double, connected: Bool) -> some Keyframes<Double> {
        let target = destination(from: phase, connected: connected)
        let distance = target - phase
        return KeyframeTrack(\.self) {
            CubicKeyframe(phase + distance * 0.16, duration: 0.22, endVelocity: distance * 1.25)
            CubicKeyframe(phase + distance * 0.84, duration: 0.54, endVelocity: distance * 0.65)
            CubicKeyframe(target, duration: 0.44, endVelocity: 0)
        }
    }
}

/// A native, event-driven animation with no sleeping task, wall-clock timer or idle timeline.
/// Restored activities begin at rest; a real reconnect within the same activity turns again.
struct NotchAirPodsConnectionGlyph: View {
    let artwork: NotchAirPodsArtwork
    let connected: Bool
    let reduceMotion: Bool
    let deviceID: String?
    let transitionRevision: UInt64
    @State private var turnRevision = 0
    @State private var introductionPending: Bool

    init(artwork: NotchAirPodsArtwork, connected: Bool, reduceMotion: Bool, turnsOnAppear: Bool = true,
         deviceID: String? = nil, transitionRevision: UInt64 = 0) {
        self.artwork = artwork
        self.connected = connected
        self.reduceMotion = reduceMotion
        self.deviceID = deviceID
        self.transitionRevision = transitionRevision
        _introductionPending = State(initialValue: turnsOnAppear && !reduceMotion)
    }

    var body: some View {
        Group {
            if !reduceMotion {
                KeyframeAnimator(initialValue: 0.0, trigger: turnRevision) { phase in
                    NotchAirPodsProductFrame(artwork: artwork, progress: NotchAirPodsMotion.pose(at: phase))
                } keyframes: { phase in
                    NotchAirPodsMotion.turn(from: phase, connected: connected)
                }
            } else {
                NotchAirPodsProductFrame(artwork: artwork, progress: 1)
            }
        }
        .opacity(connected ? 1 : 0.72)
        .onAppear {
            if introductionPending {
                introductionPending = false
                turnRevision &+= 1
            }
        }
        .onChange(of: TurnKey(artwork: artwork, connected: connected, deviceID: deviceID,
                             revision: transitionRevision)) { _, _ in
            if !reduceMotion { turnRevision &+= 1 }
        }
        .accessibilityHidden(true)
    }

    private struct TurnKey: Equatable {
        let artwork: NotchAirPodsArtwork
        let connected: Bool
        let deviceID: String?
        let revision: UInt64
    }
}

/// Prepared crops keep the rendered silhouette volumetric at every angle, with a fixed layout.
struct NotchAirPodsProductFrame: View {
    let artwork: NotchAirPodsArtwork
    let progress: Double

    var body: some View {
        if let image = artwork.image(at: progress) {
            Image(decorative: image, scale: 4)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            // Resource failures still leave a recognizable device and spoken connection status.
            Image(systemName: fallbackSymbol)
                .font(.system(size: 14, weight: .medium))
                .accessibilityHidden(true)
        }
    }

    private var fallbackSymbol: String {
        switch artwork {
        case .airPods: "airpods"
        case .airPodsPro: "airpodspro"
        case .airPodsMax: "airpodsmax"
        }
    }
}
