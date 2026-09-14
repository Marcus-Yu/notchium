import SwiftUI
import NotchiumServices
import NotchiumDynamicIsland

/// Seven bands of real system-audio energy. There is no view-owned timer.
public struct MediaWaveform: View {
    public let isPlaying: Bool
    @ObservedObject private var meter: SystemAudioMeter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(isPlaying: Bool, meter: SystemAudioMeter) {
        self.isPlaying = isPlaying; self.meter = meter
    }
    public var body: some View {
        let levels = isPlaying && !reduceMotion ? meter.waveformLevels : SystemAudioMeter.staticLevels
        HStack(spacing: 1.5) {
            ForEach(0..<7) { band in
                Capsule().fill(.white)
                    .frame(width: 2, height: 16 * levels[band])
            }
        }
        .frame(width: 24, height: 16)
        .transaction { $0.animation = nil }
        .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}

public struct CollapsedMediaView: View {
    let model: MediaFeatureModel
    let geometry: CollapsedMediaGeometry
    public init(model: MediaFeatureModel, hardwareWidth: CGFloat, hardwareHeight: CGFloat = 32) {
        self.model = model
        geometry = .init(hardwareWidth: hardwareWidth, hardwareHeight: hardwareHeight)
    }
    public var body: some View {
        HStack(spacing: 0) {
            MediaArtworkSlot(url: model.state.artwork, size: geometry.artworkSize, expanded: false)
                .frame(width: geometry.leadingWidth)
            Color.black.frame(width: geometry.hardwareWidth)
            MediaWaveform(isPlaying: model.state.isPlaying, meter: model.audioMeter).frame(width: geometry.trailingWidth)
        }
        .frame(width: geometry.width, height: geometry.height)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notchium.media.collapsed")
    }
}

public struct MediaPageView: View {
    let model: MediaFeatureModel
    public init(model: MediaFeatureModel) { self.model = model }
    public var body: some View {
        Group {
            if model.state.hasMedia {
                HStack(spacing: 14) {
                    MediaArtworkSlot(url: model.state.artwork, size: 90, expanded: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.state.title ?? "").font(.system(size: 17, weight: .semibold))
                            .lineLimit(1).truncationMode(.tail)
                        Text(model.state.artist ?? "").font(.system(size: 13, weight: .regular)).foregroundStyle(.gray)
                            .lineLimit(1).truncationMode(.tail)
                        MediaProgressView(model: model).padding(.top, 4)
                        controls.padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
            } else { Color.clear }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
        .accessibilityIdentifier("notchium.media.page")
    }
    private var controls: some View {
        HStack(spacing: 12) {
            control("Shuffle", symbol: "shuffle", command: .setShuffle(model.state.shuffle != true),
                    enabled: model.state.canShuffle, active: model.state.shuffle == true, inactiveOpacity: 0.6)
            control("Previous Track", symbol: "backward.fill", command: .previous,
                    enabled: model.state.canSkipBackward, pending: model.isPreviousPending)
            control(model.state.isPlaying ? "Pause" : "Play", symbol: model.state.isPlaying ? "pause.fill" : "play.fill",
                    command: .playPause, enabled: model.state.canPlayPause)
            control("Next Track", symbol: "forward.fill", command: .next, enabled: model.state.canSkipForward)
            control("Repeat", symbol: model.state.repeatMode == .track ? "repeat.1" : "repeat",
                    command: .setRepeatMode(model.state.repeatMode == .off ? .context : model.state.repeatMode == .context ? .track : .off),
                    enabled: model.state.canRepeat, active: model.state.repeatMode != nil && model.state.repeatMode != .off,
                    inactiveOpacity: 0.6)
        }
        .buttonStyle(MediaControlButtonStyle()).font(.system(size: 14))
        .frame(maxWidth: .infinity)
    }
    private func control(_ label: String, symbol: String, command: MediaCommand, enabled: Bool,
                         active: Bool = false, pending: Bool? = nil, inactiveOpacity: Double = 1) -> some View {
        let isAvailable = enabled && !(pending ?? model.isPending(command))
        let foregroundOpacity = isAvailable ? (active ? 1 : inactiveOpacity) : 0.45
        return Button {
            guard isAvailable else { return }
            model.send(command)
        } label: {
            Image(systemName: symbol).frame(width: 32, height: 32).contentShape(Rectangle())
        }
            .foregroundStyle(.white.opacity(foregroundOpacity))
            .accessibilityRespondsToUserInteraction(isAvailable)
            .help(label).accessibilityLabel(label)
    }
}

private struct MediaControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
