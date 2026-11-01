import SwiftUI
import NotchiumDesignSystem
import NotchiumDynamicIsland
import NotchiumServices

struct HomeMediaView: View {
    let model: MediaSessionController
    let openMusic: @MainActor () -> Void
    @Environment(\.homeUsesCompactLayout) private var compact
    @NotchReducedMotion private var reduceMotion

    var body: some View {
        Group {
            if model.homeMediaConnected && model.state.hasMedia {
                VStack(spacing: 0) {
                    information
                    Spacer(minLength: compact ? 4 : 10)
                    MediaProgressView(model: model)
                    controls.padding(.top, compact ? 2 : 8)
                }
            } else {
                Button(action: openMusic) {
                    VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                        Image(systemName: "music.note").font(.system(size: compact ? 20 : 24, weight: .light))
                            .foregroundStyle(ExpandedPageStyle.secondary)
                        Text(model.homeMediaConnected ? "Nothing playing" : "Enable Spotify")
                            .font(.system(size: compact ? 12 : 13, weight: .medium))
                        Text(model.homeMediaConnected ? "Your next listening moment." : "Your music, right here.")
                            .font(.system(size: compact ? 10 : 11)).foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, compact ? ExpandedPageStyle.Space.xs : ExpandedPageStyle.Space.sm)
        .background {
            // Background and transport are siblings, never a nested navigation button.
            Button(action: openMusic) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityHidden(true)
        }
        .accessibilityIdentifier("notchium.home.media")
    }

    private var information: some View {
        Button(action: openMusic) {
            HStack(alignment: .top, spacing: compact ? ExpandedPageStyle.Space.sm : ExpandedPageStyle.groupGap) {
                MediaArtwork(url: model.state.artwork, size: compact ? 56 : 72)
                VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                    Text(model.state.title ?? "").font(.system(size: compact ? 14 : 15, weight: .semibold))
                        .lineLimit(2)
                        .help(model.state.title ?? "")
                        .contentTransition(.opacity)
                        .animation(NotchMotionStyle.contentChange(reduceMotion: reduceMotion), value: model.state.title)
                    Text(model.state.artist ?? "").font(.system(size: compact ? 12 : 13))
                        .foregroundStyle(ExpandedPageStyle.secondary).lineLimit(1)
                        .help(model.state.artist ?? "")
                        .contentTransition(.opacity)
                        .animation(NotchMotionStyle.contentChange(reduceMotion: reduceMotion), value: model.state.artist)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Keep spare capacity below the title/artist pair, rather than
                // reserving an empty title line between those related strings.
                .frame(height: compact ? 56 : 72, alignment: .topLeading)
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
        let isAvailable = enabled && !model.isPending(command)
        return Button { model.send(command) } label: {
            Image(systemName: symbol).font(.system(size: command == .playPause ? 15 : 12, weight: .semibold))
                .contentTransition(.opacity)
                .frame(width: 34, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(MediaControlButtonStyle())
        .disabled(!isAvailable)
        .animation(NotchMotionStyle.feedback(reduceMotion: reduceMotion), value: symbol)
        .animation(NotchMotionStyle.feedback(reduceMotion: reduceMotion), value: isAvailable)
        .help(model.errorMessage ?? title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("notchium.home.media.\(command.controlID)")
    }
}
