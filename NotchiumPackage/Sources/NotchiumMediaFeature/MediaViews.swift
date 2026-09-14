import SwiftUI
import NotchiumServices
import NotchiumDynamicIsland

/// Decorative playback motion, never audio-derived. No scheduler exists in the still branch.
public struct MediaWaveform: View {
    public let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var reducedLuminance
    public init(isPlaying: Bool) { self.isPlaying = isPlaying }
    public var body: some View {
        Group {
            if isPlaying && !reduceMotion && !reducedLuminance && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                TimelineView(.animation(minimumInterval: 1 / 15)) { context in
                    bars(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else { bars(time: 0) }
        }
        .frame(width: 16, height: 12)
        .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
    private func bars(time: Double) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<5) { bar in
                Capsule().fill(.white)
                    .frame(width: 2, height: 3 + 9 * abs(sin(time * 2.4 + Double(bar) * 0.8)))
            }
        }
        .animation(.linear(duration: 1 / 15), value: time)
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
            HStack(spacing: 6) {
                MediaArtworkSlot(url: model.state.artwork, size: geometry.artworkSize, expanded: false)
                Group {
                    if geometry.height >= 30 {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(model.state.collapsedTitle).font(.system(size: 10, weight: .semibold))
                            Text(model.state.artist ?? "").font(.system(size: 9)).foregroundStyle(.gray)
                        }
                    } else {
                        Text("\(model.state.collapsedTitle) · \(model.state.artist ?? "")")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6).frame(width: geometry.leadingWidth)
            Color.black.frame(width: geometry.hardwareWidth)
            MediaWaveform(isPlaying: model.state.isPlaying).frame(width: geometry.trailingWidth)
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
                        Text(model.state.title ?? "").font(.system(size: 14, weight: .semibold))
                            .lineLimit(1).truncationMode(.tail)
                        Text(model.state.artist ?? "").font(.system(size: 12)).foregroundStyle(.gray)
                            .lineLimit(1).truncationMode(.tail)
                        MediaProgressView(model: model).padding(.top, 4)
                        controls.padding(.top, 4)
                        if let error = model.errorMessage {
                            Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
            } else { Color.clear }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("notchium.media.page")
    }
    private var controls: some View {
        HStack(spacing: 24) {
            control("Previous", symbol: "backward.end.fill", command: .previous, enabled: model.state.canSkipBackward)
            control(model.state.isPlaying ? "Pause" : "Play", symbol: model.state.isPlaying ? "pause.fill" : "play.fill",
                    command: .playPause, enabled: model.state.canPlayPause)
            control("Next", symbol: "forward.end.fill", command: .next, enabled: model.state.canSkipForward)
        }
        .buttonStyle(.plain).font(.system(size: 14))
        .frame(maxWidth: .infinity)
    }
    private func control(_ label: String, symbol: String, command: MediaCommand, enabled: Bool) -> some View {
        Button { model.send(command) } label: { Image(systemName: symbol).frame(width: 20, height: 24) }
            .disabled(!enabled || model.isBusy).opacity(enabled ? 1 : 0.3)
            .help(label).accessibilityLabel(label)
    }
}
