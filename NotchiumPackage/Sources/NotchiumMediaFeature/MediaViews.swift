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
    @State private var selectedSurface = MediaSurface.player
    @Environment(\.notchMediaExpanded) private var isExpanded
    @Environment(\.openSettings) private var openSettings
    public init(model: MediaFeatureModel) { self.model = model }
    public var body: some View {
        Group {
            switch model.state.experienceState {
            case .playing, .paused:
                VStack(spacing: 5) {
                    MediaSurfacePicker(selection: $selectedSurface)
                    Group {
                        switch selectedSurface {
                        case .player:
                            player
                        case .upNext:
                            UpNextView(state: model.state)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 24)
            case .initializing:
                statusView(title: "Spotify", message: "Restoring your Spotify session…", showsProgress: true)
            case .authorizing:
                statusView(title: "Spotify", message: "Connecting Spotify…", showsProgress: true)
            case .unauthenticated:
                statusView(title: "Spotify", message: "Connect Spotify to show and control playback.",
                           actionTitle: "Connect Spotify")
            case .inactive:
                statusView(title: "Spotify", message: model.state.issue ?? "No active playback. Open Spotify and start playing.")
            case .error:
                statusView(title: "Spotify", message: model.state.issue ?? "Spotify could not restore your session.",
                           actionTitle: "Open Settings")
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
        .accessibilityIdentifier("notchium.media.page")
        .task(id: isExpanded && selectedSurface == .upNext) {
            guard isExpanded, selectedSurface == .upNext else { return }
            await model.loadQueue()
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { selectedSurface = .player }
        }
    }
    private func statusView(title: String, message: String, showsProgress: Bool = false,
                            actionTitle: String? = nil) -> some View {
        VStack(spacing: 8) {
            if showsProgress {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .semibold))
            }
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let actionTitle {
                Button(actionTitle) { openSettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notchium.media.status.\(model.state.experienceState.rawValue)")
    }
    private var player: some View {
        HStack(spacing: 14) {
            MediaArtworkSlot(url: model.state.artwork, size: 88, expanded: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.state.title ?? "").font(.system(size: 17, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                HStack(spacing: 8) {
                    Text(model.state.artist ?? "")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    MediaWaveform(isPlaying: model.state.isPlaying, meter: model.audioMeter)
                }
                MediaProgressView(model: model).padding(.top, 3)
                controls.padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

private enum MediaSurface: String, CaseIterable, Identifiable {
    case player = "Player"
    case upNext = "Up Next"
    var id: Self { self }
}

private struct MediaSurfacePicker: View {
    @Binding var selection: MediaSurface

    var body: some View {
        HStack(spacing: 12) {
            ForEach(MediaSurface.allCases) { surface in
                Button(surface.rawValue) { selection = surface }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: surface == selection ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(surface == selection ? 1 : 0.5))
                    .accessibilityAddTraits(surface == selection ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media view")
    }
}

struct UpNextView: View {
    let state: MediaState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Up Next")
                .font(.system(size: 13, weight: .semibold))
            if state.queueIssue != nil {
                queueMessage("Unavailable")
            } else if state.queue.isEmpty {
                queueMessage("Nothing queued")
            } else {
                ForEach(state.queue.prefix(3)) { track in
                    QueueTrackRow(track: track)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .accessibilityIdentifier("notchium.media.up-next")
    }

    private func queueMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct QueueTrackRow: View {
    let track: QueueTrack

    var body: some View {
        HStack(spacing: 8) {
            MediaArtwork(url: track.artworkURL, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(track.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(track.title), \(track.artist)")
    }
}

private struct MediaControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
