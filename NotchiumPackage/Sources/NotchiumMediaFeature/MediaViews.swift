import SwiftUI
import NotchiumDesignSystem
import NotchiumServices
import NotchiumDynamicIsland

/// Seven bands of real system-audio energy. There is no view-owned timer.
public struct MediaWaveform: View {
    public let isPlaying: Bool
    public let color: Color
    public let isPresented: Bool
    private let meter: SystemAudioMeter
    @NotchReducedMotion private var reduceMotion
    public init(isPlaying: Bool, meter: SystemAudioMeter, color: Color = .white, isPresented: Bool = true) {
        self.isPlaying = isPlaying; self.meter = meter; self.color = color
        self.isPresented = isPresented
    }
    @ViewBuilder
    public var body: some View {
        // Hidden surfaces and Reduce Motion must not subscribe to audio samples.
        let isVisible = isPresented && isPlaying && !reduceMotion && meter.isAudioActive
        Group {
            if isVisible {
                HStack(spacing: 1.5) {
                    ForEach(0..<7) { band in
                        Capsule().fill(color)
                            .frame(width: 2, height: 16 * meter.waveformLevels[band])
                    }
                }
                .frame(width: 24, height: 16)
                .transition(.opacity.combined(with: .scale(scale: 0.86)))
                .accessibilityHidden(true)
            }
        }
        .animation(MediaMotion.waveform(reduceMotion: reduceMotion), value: isVisible)
    }
}

struct CollapsedMediaWaveform: View {
    let model: MediaFeatureModel
    @Environment(\.notchMediaExpanded) private var isExpanded

    var body: some View {
        MediaWaveform(isPlaying: model.state.isPlaying, meter: model.audioMeter,
                      color: model.waveformAppearance.color, isPresented: !isExpanded)
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
            CollapsedMediaWaveform(model: model)
                .frame(width: geometry.trailingWidth)
        }
        .frame(width: geometry.width, height: geometry.height)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notchium.media.collapsed")
    }
}

private enum MusicPlayerSpacing {
    static let metadataRowHeight: CGFloat = 84
    static let metadataGap: CGFloat = 6
    static let metadataToProgress: CGFloat = 5
    static let outputRowHeight: CGFloat = 26
    static let playerHeight = metadataRowHeight + 2 * ExpandedPageStyle.groupGap + 2 * ExpandedPageStyle.controlSize
    // Match the visible source logo's bottom edge within the 32-point output row.
    static let artworkSize = playerHeight - (ExpandedPageStyle.controlSize - ExpandedPageStyle.compactControlSize) / 2
}

public struct MediaPageView: View {
    let model: MediaFeatureModel
    @State private var presentationID = UUID().uuidString
    @Environment(\.notchMediaExpanded) private var isExpanded
    @Environment(\.notchMediaPageVisible) private var isPageVisible
    @Environment(\.openSettings) private var openSettings
    @NotchReducedMotion private var reduceMotion
    public init(model: MediaFeatureModel) { self.model = model }
    public var body: some View {
        Group {
            switch model.state.experienceState {
            case .playing, .paused: player
            case .initializing:
                statusView(title: "Spotify", message: "Checking local Spotify…", showsProgress: true)
            case .authorizing:
                statusView(title: "Spotify", message: "Allow Spotify control in the macOS dialog.", showsProgress: true)
            case .unauthenticated:
                statusView(title: "Spotify", message: model.state.issue ?? LocalSpotifyStatus.needsPermission.message,
                           actionTitle: "Enable Local Control", action: { model.enableLocalControl() })
            case .inactive:
                statusView(title: "Spotify", message: model.state.issue ?? "Play a song in Spotify to get started.",
                           actionTitle: model.state.localSpotifyStatus == .notRunning ? "Open Spotify" : nil,
                           action: { model.openSpotify() })
            case .error:
                statusView(title: "Spotify", message: model.state.issue ?? "Spotify couldn’t refresh playback.",
                           actionTitle: model.state.localSpotifyStatus == .denied ? "Open System Settings" : "Open Settings",
                           action: {
                               if model.state.localSpotifyStatus == .denied { SpotifyAutomationSettings.open() }
                               else { openSettings() }
                           })
            }
        }
        .padding(.horizontal, ExpandedPageStyle.outerInset)
        .padding(.top, ExpandedPageStyle.topInset)
        .padding(.bottom, ExpandedPageStyle.bottomInset)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("notchium.media.page")
        .task(id: isExpanded && isPageVisible) {
            await model.setExpandedVisible(isExpanded && isPageVisible, source: presentationID)
        }
        .onDisappear {
            let source = presentationID
            Task { await model.removePresentation(source: source) }
        }
    }
    private func statusView(title: String, message: String, showsProgress: Bool = false,
                            actionTitle: String? = nil, action: @escaping () -> Void = {}) -> some View {
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
                Button(actionTitle, action: action)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .overlay(alignment: .bottomTrailing) {
            MediaSourceButton(source: model.state.source ?? .spotify)
                .padding(.trailing, ExpandedPageStyle.outerInset - MediaSourceButton.contentInset)
                .padding(.bottom, ExpandedPageStyle.bottomInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notchium.media.status.\(model.state.experienceState.rawValue)")
    }
    private var player: some View {
        HStack(alignment: .top, spacing: ExpandedPageStyle.Space.lg) {
            MediaArtworkSlot(url: model.state.artwork, size: MusicPlayerSpacing.artworkSize, expanded: true)
            VStack(spacing: ExpandedPageStyle.groupGap) {
                trackDetails
                    .frame(height: MusicPlayerSpacing.metadataRowHeight)
                controls
                HStack(spacing: ExpandedPageStyle.Space.lg) {
                    SpotifyVolumeControl(model: model)
                        .frame(maxWidth: .infinity)
                    MediaSourceButton(source: model.state.source ?? .spotify)
                        // Align the logo artwork while retaining its padded hit target.
                        .padding(.trailing, -MediaSourceButton.contentInset)
                }
                .frame(height: ExpandedPageStyle.controlSize)
            }
            .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    private var trackDetails: some View {
        let trackIdentity = model.state.trackID ?? model.state.title ?? "unknown-track"
        return VStack(alignment: .leading, spacing: MusicPlayerSpacing.metadataToProgress) {
            HStack(alignment: .center, spacing: ExpandedPageStyle.Space.sm) {
                VStack(alignment: .leading, spacing: MusicPlayerSpacing.metadataGap) {
                    Text(model.state.title ?? "")
                        .font(ExpandedPageStyle.title)
                        .lineLimit(1).truncationMode(.tail)
                        .help(model.state.title ?? "")
                    Text(model.state.artist ?? "")
                        .font(ExpandedPageStyle.body)
                        .foregroundStyle(ExpandedPageStyle.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MediaWaveform(isPlaying: model.state.isPlaying, meter: model.audioMeter,
                              color: model.waveformAppearance.color,
                              isPresented: isExpanded && isPageVisible)
                    .frame(width: 24, height: 16)
            }
            .id(trackIdentity)
            .transition(.opacity)
            .animation(MediaMotion.track(reduceMotion: reduceMotion), value: trackIdentity)
            .opacity(model.isShowingCachedTrack ? 0.94 : 1)
            MediaProgressView(model: model)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var controls: some View {
        HStack(spacing: ExpandedPageStyle.Space.lg) {
            control("Shuffle", symbol: "shuffle", command: .setShuffle(model.state.shuffle != true),
                    enabled: model.state.canShuffle, active: model.state.shuffle == true, inactiveOpacity: 0.65,
                    value: model.state.shuffle.map { $0 ? "On" : "Off" } ?? "Unavailable")
            control("Previous Track", symbol: "backward.fill", command: .previous,
                    enabled: model.state.canSkipBackward, pending: model.isPreviousPending)
            control(model.state.isPlaying ? "Pause" : "Play", symbol: model.state.isPlaying ? "pause.fill" : "play.fill",
                    command: .playPause, enabled: model.state.canPlayPause)
            control("Next Track", symbol: "forward.fill", command: .next, enabled: model.state.canSkipForward)
            control("Repeat", symbol: model.state.repeatMode == .track ? "repeat.1" : "repeat",
                    command: .setRepeatMode(model.state.repeatMode == .off ? .context : .off),
                    enabled: model.state.canRepeat, active: model.state.repeatMode != nil && model.state.repeatMode != .off,
                    inactiveOpacity: 0.65, value: repeatModeValue)
        }
        .buttonStyle(MediaControlButtonStyle())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback controls")
    }
    private func control(_ label: String, symbol: String, command: MediaCommand, enabled: Bool,
                         active: Bool = false, pending: Bool? = nil, inactiveOpacity: Double = 1,
                         value: String? = nil) -> some View {
        let isAvailable = enabled && !(pending ?? model.isPending(command))
        let foregroundOpacity = isAvailable ? (active ? 1 : inactiveOpacity) : 0.45
        return Button {
            guard isAvailable else { return }
            model.send(command)
        } label: {
            Image(systemName: symbol)
                .contentTransition(.opacity)
                .font(.system(size: command == .playPause ? 16 : 13, weight: .semibold))
                .frame(width: ExpandedPageStyle.controlSize, height: ExpandedPageStyle.controlSize)
                .background(.white.opacity(command == .playPause ? 0.18 : (active ? 0.10 : 0)), in: .circle)
                .overlay(alignment: .bottom) {
                    if active { Circle().fill(.white).frame(width: 3, height: 3) }
                }
                .contentShape(.circle)
        }
            .foregroundStyle(.white.opacity(foregroundOpacity))
            .disabled(!isAvailable)
            .animation(MediaMotion.control(reduceMotion: reduceMotion), value: symbol)
            .animation(MediaMotion.control(reduceMotion: reduceMotion), value: active)
            .accessibilityRespondsToUserInteraction(isAvailable)
            .help(label).accessibilityLabel(label)
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var repeatModeValue: String {
        switch model.state.repeatMode {
        case .off: "Off"
        case .context: "All tracks"
        case .track: "One track"
        case nil: "Unavailable"
        }
    }
}

private struct SpotifyVolumeControl: View {
    let model: MediaFeatureModel
    @State private var isAdjustingVolume = false
    @State private var volume = 0.5

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: volumeSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(model.state.capabilities.canSetVolume ? 0.78 : 0.38))
                .frame(width: 16)

            NotchiumSlider(
                value: Binding(
                    get: { volume },
                    set: { value in
                        volume = value
                        model.setVolume(value, final: false)
                    }
                ),
                accessibilityLabel: "Spotify volume",
                accessibilityStep: 0.05,
                accessibilityValue: { "\(Int(($0 * 100).rounded())) percent" }
            ) { editing in
                if editing {
                    isAdjustingVolume = true
                    syncVolume()
                } else {
                    model.setVolume(volume, final: true)
                    isAdjustingVolume = false
                }
            }
            .frame(maxWidth: .infinity, minHeight: 20)
            .disabled(!model.state.capabilities.canSetVolume)
            .help(model.state.capabilities.canSetVolume
                  ? "Spotify volume"
                  : "Spotify volume is unavailable")

            Text("\(Int((volume * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 36, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(height: MusicPlayerSpacing.outputRowHeight)
        .onAppear { syncVolume() }
        .onChange(of: model.state.volumePercent) { _, _ in
            if !isAdjustingVolume { syncVolume() }
        }
        .onChange(of: model.state.capabilities.canSetVolume) { _, canSetVolume in
            if !canSetVolume {
                isAdjustingVolume = false
                syncVolume()
            }
        }
    }

    private var volumeSymbol: String {
        if volume == 0 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func syncVolume() {
        volume = Double(model.state.volumePercent ?? 50) / 100
    }
}

struct MediaControlButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        MediaControlFeedback(configuration: configuration)
    }
}

private struct MediaControlFeedback: View {
    let configuration: ButtonStyleConfiguration
    @NotchReducedMotion private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(.white.opacity(isHovered && isEnabled ? 0.08 : 0),
                        in: .rect(cornerRadius: ExpandedPageStyle.controlRadius))
            .onHover { isHovered = $0 }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(MediaMotion.control(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

private enum MediaMotion {
    static func control(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.16)
    }

    static func surface(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.26)
    }

    static func track(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.22)
    }

    static func waveform(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.2)
    }
}
