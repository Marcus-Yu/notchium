import SwiftUI
import NotchiumServices

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
        .frame(width: 22, height: 20)
        .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
    private func bars(time: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<6) { bar in
                Capsule().fill(.white)
                    .frame(width: 2, height: 4 + 14 * abs(sin(time * 2.4 + Double(bar) * 0.8)))
            }
        }
        .animation(.linear(duration: 1 / 15), value: time)
    }
}

public struct CollapsedMediaView: View {
    let model: MediaFeatureModel
    let hardwareWidth: CGFloat
    public init(model: MediaFeatureModel, hardwareWidth: CGFloat) {
        self.model = model; self.hardwareWidth = hardwareWidth
    }
    public var body: some View {
        let wingWidth = max(0, (360 - hardwareWidth) / 2)
        HStack(spacing: 0) {
            HStack {
                MediaArtwork(url: model.state.artwork, size: 24)
                Spacer(minLength: 0)
            }.padding(.leading, 8).frame(width: wingWidth)
            Color.clear.frame(width: hardwareWidth)
            HStack(spacing: 5) {
                Text(model.state.collapsedTitle).font(.system(size: 11, weight: .medium))
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                MediaWaveform(isPlaying: model.state.isPlaying)
            }.padding(.horizontal, 6).frame(width: wingWidth)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notchium.media.collapsed")
    }
}

public struct MediaPageView: View {
    let model: MediaFeatureModel
    @State private var seekValue = 0.0
    @State private var isSeeking = false
    @State private var showsQueue = false
    public init(model: MediaFeatureModel) { self.model = model }
    public var body: some View {
        Group {
            if model.state.hasMedia {
                HStack(spacing: 16) {
                    MediaArtwork(url: model.state.artwork, size: 88)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.state.title ?? "").font(.system(size: 14, weight: .semibold))
                            .lineLimit(1).truncationMode(.tail)
                        Text(model.state.artist ?? "").font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        progress
                        controls
                        if let error = model.errorMessage {
                            Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            } else { Color.clear }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.state.trackID) { _, _ in isSeeking = false; showsQueue = false }
        .accessibilityIdentifier("notchium.media.page")
    }
    private var progress: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { isSeeking ? seekValue : model.state.elapsedTime },
                                  set: { seekValue = $0 }),
                   in: 0...max(1, model.state.validDuration ?? 1)) { Text("Playback position") }
            onEditingChanged: { editing in
                if editing { seekValue = model.state.elapsedTime; isSeeking = true }
                else { isSeeking = false; model.send(.seek(seekValue)) }
            }
            .disabled(!model.state.canSeek || model.isBusy)
            .labelsHidden().controlSize(.mini).tint(.white)
            HStack {
                Text(Self.time(model.state.elapsedTime))
                Spacer()
                Text(model.state.validDuration.map(Self.time) ?? "–:––")
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
        }
    }
    private var controls: some View {
        HStack(spacing: 12) {
            if model.state.capabilities.canShuffle {
                control("Shuffle", symbol: "shuffle", command: .toggleShuffle, enabled: true)
                    .foregroundStyle(model.state.shuffle == true ? .green : .white)
            }
            control("Previous", symbol: "backward.end.fill", command: .previous, enabled: model.state.canSkipBackward)
            control(model.state.isPlaying ? "Pause" : "Play", symbol: model.state.isPlaying ? "pause.fill" : "play.fill",
                    command: .playPause, enabled: model.state.canPlayPause)
            control("Next", symbol: "forward.end.fill", command: .next, enabled: model.state.canSkipForward)
            if model.state.capabilities.canRepeat {
                control("Repeat", symbol: model.state.repeatMode == .track ? "repeat.1" : "repeat",
                        command: .cycleRepeat, enabled: true)
                    .foregroundStyle(model.state.repeatMode != .off ? .green : .white)
            }
            if model.state.capabilities.canReadQueue {
                Button { showsQueue.toggle() } label: { Image(systemName: "list.bullet") }
                    .help("Up Next").accessibilityLabel("Up Next")
                    .popover(isPresented: $showsQueue) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Up Next").font(.headline)
                            if let queue = model.state.queue {
                                if queue.isEmpty { Text("Queue is empty").foregroundStyle(.secondary) }
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(queue) { item in
                                            VStack(alignment: .leading) {
                                                Text(item.title).lineLimit(1)
                                                Text(item.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            } else { Text(model.errorMessage ?? "Loading queue…").font(.caption) }
                        }.padding().frame(width: 250, height: 170).task { await model.loadQueue() }
                    }
            }
        }
        .buttonStyle(.plain).font(.system(size: 12)).padding(.top, 3)
    }
    private func control(_ label: String, symbol: String, command: MediaCommand, enabled: Bool) -> some View {
        Button { model.send(command) } label: { Image(systemName: symbol).frame(width: 20, height: 24) }
            .disabled(!enabled || model.isBusy).opacity(enabled ? 1 : 0.3)
            .help(label).accessibilityLabel(label)
    }
    private static func time(_ seconds: Double) -> String {
        let value = Int(min(max(0, seconds), 86_400))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
