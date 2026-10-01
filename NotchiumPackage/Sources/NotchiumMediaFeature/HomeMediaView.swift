import SwiftUI
import NotchiumDesignSystem
import NotchiumDynamicIsland
import NotchiumServices

struct HomeMediaView: View {
    let model: MediaSessionController
    let openMusic: @MainActor () -> Void

    var body: some View {
        Group {
            if model.homeMediaConnected && model.state.hasMedia {
                VStack(spacing: 0) {
                    information
                    connectControl.padding(.top, 8)
                    Spacer(minLength: 10)
                    MediaProgressView(model: model)
                    controls.padding(.top, 8)
                }
            } else {
                Button(action: openMusic) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "music.note").font(.system(size: 24, weight: .light))
                            .foregroundStyle(ExpandedPageStyle.secondary)
                        Text(model.homeMediaConnected ? "Nothing playing" : "Connect Spotify")
                            .font(.system(size: 13, weight: .medium))
                        Text(model.homeMediaConnected ? "Your next listening moment." : "Your music, right here.")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, ExpandedPageStyle.Space.sm)
        .background {
            // Background and transport are siblings, never a nested navigation button.
            Button(action: openMusic) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityHidden(true)
        }
        .accessibilityIdentifier("notchium.home.media")
        .onAppear { model.refreshDevicesIfStale() }
        .onChange(of: model.homeMediaConnected) { _, connected in
            if connected { model.refreshDevicesIfStale() }
        }
    }

    private var connectControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "hifispeaker.and.homepod.fill").foregroundStyle(ExpandedPageStyle.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Spotify Connect").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ExpandedPageStyle.secondary)
                Text(model.connectActiveDeviceName).font(.system(size: 10)).lineLimit(1)
            }
            Spacer(minLength: 2)
            if model.devicesLoading { ProgressView().controlSize(.mini).tint(.white) }
            else { Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(ExpandedPageStyle.secondary) }
            Button {
                if let target = model.connectTarget { model.transferPlayback(to: target) }
            } label: {
                Text(model.connectTargetName).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .padding(.horizontal, 7).frame(height: 24)
                    .background(.white.opacity(0.1), in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(model.connectTarget == nil || model.devicesLoading)
            .help(model.deviceIssue ?? (model.connectTarget == nil ? "Device unavailable" : "Transfer playback"))
            .accessibilityLabel("Transfer Spotify to \(model.connectTargetName)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(model.devicesLoading ? "Connecting" : "Active: \(model.connectActiveDeviceName)")
        .accessibilityIdentifier("notchium.home.spotify-connect")
    }

    private var information: some View {
        Button(action: openMusic) {
            HStack(spacing: ExpandedPageStyle.groupGap) {
                MediaArtwork(url: model.state.artwork, size: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.state.title ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(model.state.artist ?? "").font(.system(size: 11))
                        .foregroundStyle(ExpandedPageStyle.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Music: \(model.state.title ?? "")")
    }

    private var controls: some View {
        HStack(spacing: 18) {
            control("Previous", symbol: "backward.fill", command: .previous,
                    enabled: model.state.canSkipBackward && !model.isPreviousPending)
            control(model.state.isPlaying ? "Pause" : "Play",
                    symbol: model.state.isPlaying ? "pause.fill" : "play.fill", command: .playPause,
                    enabled: model.state.canPlayPause)
            control("Next", symbol: "forward.fill", command: .next, enabled: model.state.canSkipForward)
        }.frame(maxWidth: .infinity)
    }

    private func control(_ title: String, symbol: String, command: MediaCommand, enabled: Bool) -> some View {
        Button { model.send(command) } label: {
            Image(systemName: symbol).font(.system(size: command == .playPause ? 15 : 12, weight: .semibold))
                .frame(width: 34, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || model.isPending(command))
        .help(model.errorMessage ?? title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("notchium.home.media.\(command.controlID)")
    }
}
