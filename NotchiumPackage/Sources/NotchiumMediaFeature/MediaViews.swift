import SwiftUI
import NotchiumDesignSystem
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
    @ViewBuilder
    public var body: some View {
        let isVisible = isPlaying && meter.isAudioActive && !reduceMotion
        Group {
            if isVisible {
                HStack(spacing: 1.5) {
                    ForEach(0..<7) { band in
                        Capsule().fill(.white)
                            .frame(width: 2, height: 16 * meter.waveformLevels[band])
                    }
                }
                .frame(width: 24, height: 16)
                .transition(.opacity.combined(with: .scale(scale: 0.86)))
                .accessibilityLabel("Local Spotify audio waveform")
            }
        }
        .animation(MediaMotion.waveform(reduceMotion: reduceMotion), value: isVisible)
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
    @State private var showsDevices = false
    @Environment(\.notchMediaExpanded) private var isExpanded
    @Environment(\.notchMediaPageVisible) private var isPageVisible
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(model: MediaFeatureModel) { self.model = model }
    public var body: some View {
        Group {
            switch model.state.experienceState {
            case .playing, .paused:
                VStack(spacing: 8) {
                    MediaSurfacePicker(selection: $selectedSurface)
                        .padding(.top, 16)
                    Group {
                        switch selectedSurface {
                        case .player:
                            player
                        case .upNext:
                            UpNextView(state: model.state)
                        }
                    }
                    .id(selectedSurface)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, NotchGeometryResolver.expandedContentHorizontalInset)
                .animation(MediaMotion.surface(reduceMotion: reduceMotion), value: selectedSurface)
            case .initializing:
                statusView(title: "Spotify", message: "Restoring your Spotify session…", showsProgress: true)
            case .authorizing:
                statusView(title: "Spotify", message: "Connecting Spotify…", showsProgress: true)
            case .unauthenticated:
                statusView(title: "Spotify", message: "Connect Spotify to show and control playback.",
                           actionTitle: "Connect Spotify")
            case .inactive:
                statusView(title: "Spotify", message: model.state.issue ?? "No recent Spotify track yet.")
            case .error:
                statusView(title: "Spotify", message: model.state.issue ?? "Spotify could not restore your session.",
                           actionTitle: "Open Settings")
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
        .accessibilityIdentifier("notchium.media.page")
        .task(id: isExpanded && isPageVisible && selectedSurface == .upNext) {
            model.setUpNextVisible(isExpanded && isPageVisible && selectedSurface == .upNext)
        }
        .task(id: isExpanded && isPageVisible) {
            await model.setExpandedVisible(isExpanded && isPageVisible)
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                selectedSurface = .player
                showsDevices = false
            }
        }
        .onChange(of: selectedSurface) { _, _ in
            showsDevices = false
        }
        .onDisappear {
            model.setUpNextVisible(false)
            Task { await model.setExpandedVisible(false) }
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
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notchium.media.status.\(model.state.experienceState.rawValue)")
    }
    private var player: some View {
        let trackIdentity = model.state.trackID ?? model.state.title ?? "unknown-track"
        return ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 20) {
                MediaArtworkSlot(url: model.state.artwork, size: 92, expanded: true)
                VStack(alignment: .leading, spacing: 7) {
                    VStack(alignment: .leading, spacing: 4) {
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
                    }
                    .id(trackIdentity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                    .animation(MediaMotion.track(reduceMotion: reduceMotion), value: trackIdentity)
                    .opacity(model.isShowingCachedTrack ? 0.94 : 1)
                    .animation(MediaMotion.track(reduceMotion: reduceMotion), value: model.isShowingCachedTrack)
                    MediaProgressView(model: model).padding(.top, 5)
                    controls.padding(.top, 5)
                    SpotifySecondaryControls(model: model, showsDevices: $showsDevices)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsDevices {
                Button {
                    showsDevices = false
                } label: {
                    Color.clear.contentShape(.rect)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .buttonStyle(.plain)
                .accessibilityHidden(true)

                SpotifyDevicesPicker(model: model) { device in
                    if device.id == model.state.activeDeviceID {
                        showsDevices = false
                    } else {
                        model.transferPlayback(to: device)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                .zIndex(1)
            }
        }
        .animation(MediaMotion.control(reduceMotion: reduceMotion), value: showsDevices)
        .onChange(of: model.state.activeDeviceID) { _, _ in
            if showsDevices && !model.devicesLoading { showsDevices = false }
        }
    }
    private var controls: some View {
        GlassEffectContainer(spacing: 28) {
            HStack(spacing: 0) {
                control("Shuffle", symbol: "shuffle", command: .setShuffle(model.state.shuffle != true),
                        enabled: model.state.canShuffle, active: model.state.shuffle == true, inactiveOpacity: 0.6)
                Spacer().frame(width: 24)
                control("Previous Track", symbol: "backward.fill", command: .previous,
                        enabled: model.state.canSkipBackward, pending: model.isPreviousPending)
                Spacer().frame(width: 28)
                control(model.state.isPlaying ? "Pause" : "Play", symbol: model.state.isPlaying ? "pause.fill" : "play.fill",
                        command: .playPause, enabled: model.state.canPlayPause)
                Spacer().frame(width: 28)
                control("Next Track", symbol: "forward.fill", command: .next, enabled: model.state.canSkipForward)
                Spacer().frame(width: 24)
                control("Repeat", symbol: model.state.repeatMode == .track ? "repeat.1" : "repeat",
                        command: .setRepeatMode(model.state.repeatMode == .off ? .context : model.state.repeatMode == .context ? .track : .off),
                        enabled: model.state.canRepeat, active: model.state.repeatMode != nil && model.state.repeatMode != .off,
                        inactiveOpacity: 0.6)
            }
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
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .contentShape(.circle)
                .glassEffect(
                    active
                        ? .regular.tint(.white.opacity(0.14)).interactive()
                        : .clear.interactive(),
                    in: .circle
                )
        }
            .foregroundStyle(.white.opacity(foregroundOpacity))
            .disabled(!isAvailable)
            .animation(MediaMotion.control(reduceMotion: reduceMotion), value: symbol)
            .animation(MediaMotion.control(reduceMotion: reduceMotion), value: active)
            .accessibilityRespondsToUserInteraction(isAvailable)
            .help(label).accessibilityLabel(label)
    }
}

private struct SpotifySecondaryControls: View {
    let model: MediaFeatureModel
    @Binding var showsDevices: Bool
    @State private var isAdjustingVolume = false
    @State private var volume = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .frame(maxWidth: 118, minHeight: 20)
            .disabled(!model.state.capabilities.canSetVolume)
            .help(model.state.capabilities.canSetVolume
                  ? "Spotify volume"
                  : "This Spotify device doesn’t support remote volume")

            if isAdjustingVolume {
                Text("\(Int((volume * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 36, alignment: .trailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Spacer(minLength: 4)

            Button {
                showsDevices.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: deviceSymbol(model.state.activeDeviceType))
                    Text(model.state.activeDeviceName ?? "Devices")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .glassEffect(.clear.interactive(), in: .capsule)
            }
            .buttonStyle(MediaControlButtonStyle())
            .help("Spotify Connect devices")
            .accessibilityLabel("Spotify Connect device, \(model.state.activeDeviceName ?? "unknown")")
            .accessibilityIdentifier("notchium.media.devices.button")
        }
        .frame(height: 28)
        .animation(MediaMotion.control(reduceMotion: reduceMotion), value: isAdjustingVolume)
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
        .onChange(of: showsDevices) { _, isPresented in
            if isPresented { model.refreshDevices() }
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

private struct SpotifyDevicesPicker: View {
    let model: MediaFeatureModel
    let onSelect: (SpotifyDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spotify Connect")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 4)

            if model.devicesLoading && model.devices.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finding devices…")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 46)
            } else if let issue = model.deviceIssue, model.devices.isEmpty {
                Text(issue)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 46)
            } else if model.devices.isEmpty {
                Text("No Spotify devices found")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 46)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.devices) { device in
                            Button {
                                onSelect(device)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: deviceSymbol(device.type))
                                        .frame(width: 17)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(device.name).lineLimit(1)
                                        if device.isRestricted {
                                            Text("Unavailable").font(.system(size: 9)).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if device.isActive || device.id == model.state.activeDeviceID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .frame(height: 34)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(device.isRestricted || model.devicesLoading)
                            .opacity(device.isRestricted ? 0.5 : 1)
                            .accessibilityAddTraits(device.isActive ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 92)
            }
        }
        .padding(10)
        .frame(width: 228)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.96))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notchium.media.devices.picker")
    }
}

private func deviceSymbol(_ type: String?) -> String {
    switch type?.lowercased() {
    case "computer": "desktopcomputer"
    case "smartphone": "iphone"
    case "tablet": "ipad"
    case "speaker": "hifispeaker.fill"
    case "tv": "tv.fill"
    case "avr": "av.receiver"
    case "automobile": "car.fill"
    default: "airplayaudio"
    }
}

private enum MediaSurface: String, CaseIterable, Identifiable {
    case player = "Player"
    case upNext = "Up Next"
    var id: Self { self }
}

private struct MediaSurfacePicker: View {
    @Binding var selection: MediaSurface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(MediaSurface.allCases) { surface in
                    Button(surface.rawValue) { selection = surface }
                        .buttonStyle(MediaControlButtonStyle())
                        .font(.system(size: 11, weight: surface == selection ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(surface == selection ? 1 : 0.62))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .glassEffect(
                            surface == selection
                                ? .regular.tint(.white.opacity(0.1)).interactive()
                                : .clear.interactive(),
                            in: .capsule
                        )
                        .accessibilityAddTraits(surface == selection ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(MediaMotion.control(reduceMotion: reduceMotion), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media view")
    }
}

struct UpNextView: View {
    let state: MediaState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .transition(.opacity.combined(with: .offset(y: 4)))
                }
            }
        }
        .animation(MediaMotion.surface(reduceMotion: reduceMotion), value: state.queue.map(\.id))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
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
