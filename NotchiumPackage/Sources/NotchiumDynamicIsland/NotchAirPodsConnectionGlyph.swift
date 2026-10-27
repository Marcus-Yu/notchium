import ImageIO
import SwiftUI

/// Original, locally rendered product artwork. Frames are evenly spaced in angle; SwiftUI
/// supplies frame updates. The first and last frame share a pose for a seamless loop.
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

/// The animation schedule lives only as long as the visible product, including retraction.
/// Banner coalescing and restoration cannot stop the loop; Reduce Motion removes it.
struct NotchAirPodsConnectionGlyph: View {
    let artwork: NotchAirPodsArtwork
    let connected: Bool
    let reduceMotion: Bool
    @State private var motion: NotchAirPodsMotion?

    var body: some View {
        Group {
            if !reduceMotion {
                TimelineView(.animation(paused: motion == nil)) { _ in
                    let phase = motion?.sample(at: .now).phase ?? 0
                    NotchAirPodsProductFrame(artwork: artwork, progress: NotchAirPodsMotion.pose(at: phase))
                }
            } else {
                NotchAirPodsProductFrame(artwork: artwork, progress: 1)
            }
        }
        .opacity(connected ? 1 : 0.72)
        .onChange(of: connected, initial: true) { _, _ in
            updateMotion()
        }
        .onChange(of: reduceMotion) { _, _ in updateMotion() }
        .accessibilityHidden(true)
    }

    private func updateMotion() {
        if reduceMotion {
            motion = nil
        } else if motion != nil {
            motion?.setConnected(connected, at: .now)
        } else {
            motion = NotchAirPodsMotion(connected: connected, at: .now)
        }
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
