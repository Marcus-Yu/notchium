import Foundation
import Observation
import SwiftUI

public enum WaveformColorMode: String, CaseIterable, Identifiable {
    case `static`, adaptive
    public var id: String { rawValue }
    var title: String { self == .static ? "Static" : "Adaptive" }
}

/// One appearance owner for every artwork-coloured surface: the waveform, and Music's accent
/// (progress, primary transport, selection). Audio samples never enter this model.
@MainActor @Observable
public final class WaveformAppearanceModel {
    public var mode: WaveformColorMode {
        didSet {
            guard mode != oldValue else { return }
            // Artwork analysis is mode-independent (Music's accent needs it), so a mode switch
            // only changes which colour the waveform resolves to.
            preferences?.set(mode.rawValue, forKey: "media.waveform.colorMode")
        }
    }
    var staticColor: WaveformColor {
        didSet {
            guard staticColor != oldValue else { return }
            preferences?.set(staticColor.hex, forKey: "media.waveform.staticColor")
        }
    }
    private(set) var artworkColor: WaveformColor?
    public var color: Color { resolvedColor.color }
    var resolvedColor: WaveformColor {
        (mode == .static ? staticColor : artworkColor ?? .white).visibleOnBlack
    }
    /// Music's accent follows the artwork in both waveform modes; nil for neutral or missing art.
    public var accentColor: Color? { artworkColor?.mutedAccent?.color }
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private let loadArtworkColor: @MainActor (URL) async -> WaveformColor?
    @ObservationIgnored private var artworkURL: URL?
    @ObservationIgnored private var artworkColorURL: URL?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    public convenience init(preferences: UserDefaults? = nil) {
        self.init(preferences: preferences) { url in
#if DEBUG
            // The drawn fixture cover (an orange sun) never reaches the network cache.
            if url.scheme == "notchium-fixture" { return WaveformColor(red: 230, green: 138, blue: 52) }
#endif
            return try? await MediaArtworkCache.shared.load(url)?.primaryColor
        }
    }

    init(preferences: UserDefaults? = nil,
         loadArtworkColor: @escaping @MainActor (URL) async -> WaveformColor?) {
        self.preferences = preferences
        self.loadArtworkColor = loadArtworkColor
        mode = preferences?.string(forKey: "media.waveform.colorMode").flatMap(WaveformColorMode.init(rawValue:)) ?? .static
        staticColor = preferences?.string(forKey: "media.waveform.staticColor").flatMap(WaveformColor.init(hex:)) ?? .white
    }

    deinit { artworkTask?.cancel() }

    @discardableResult
    func setStaticHex(_ hex: String) -> Bool {
        guard let color = WaveformColor(hex: hex) else { return false }
        staticColor = color
        return true
    }

    func setArtwork(_ url: URL?) {
        guard artworkURL != url else { return }
        artworkURL = url
        // Keep the displayed colour while the next album loads, avoiding a white flash.
        if url == nil { artworkColor = nil; artworkColorURL = nil }
        refreshArtworkColor()
    }

    /// The artwork is analysed once per cover in both modes, because Music's accent always
    /// follows it; only the waveform's own colour depends on the mode.
    private func refreshArtworkColor() {
        artworkTask?.cancel(); artworkTask = nil
        guard let url = artworkURL, artworkColorURL != url else { return }
        let load = loadArtworkColor
        artworkTask = Task { [weak self] in
            let color = await load(url)
            guard !Task.isCancelled, let self, self.artworkURL == url else { return }
            self.artworkColor = color
            self.artworkColorURL = color == nil ? nil : url
            self.artworkTask = nil
        }
    }
}
