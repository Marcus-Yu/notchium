import SwiftUI
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
                    Spacer(minLength: 10)
                    HomeMediaProgress(model: model)
                        .allowsHitTesting(false)
                    controls.padding(.top, 8)
                }
            } else {
                Button(action: openMusic) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "music.note").font(.system(size: 24, weight: .light))
                            .foregroundStyle(.white.opacity(0.35))
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
        .padding(12)
        .background {
            // Background and transport are siblings, never a nested navigation button.
            Button(action: openMusic) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityHidden(true)
        }
        .accessibilityIdentifier("notchium.home.media")
    }

    private var information: some View {
        Button(action: openMusic) {
            HStack(spacing: 12) {
                MediaArtwork(url: model.state.artwork, size: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.state.title ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(model.state.artist ?? "").font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5)).lineLimit(1)
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

/// Lightweight read-only progress; shares Music's authoritative position estimate.
private struct HomeMediaProgress: View {
    let model: MediaSessionController
    @Environment(\.notchMediaExpanded) private var isExpanded

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !model.state.isPlaying || !isExpanded)) { timeline in
            let elapsed = model.displayedPosition(at: timeline.date, uptime: ProcessInfo.processInfo.systemUptime)
            let duration = model.state.validDuration
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(.white.opacity(0.65))
                        .frame(width: geometry.size.width * (duration.map { min(max(elapsed / $0, 0), 1) } ?? 0))
                }.frame(height: 2)
                HStack {
                    Text(MediaProgressView.time(elapsed))
                    Spacer()
                    Text(duration.map(MediaProgressView.time) ?? "–:––")
                }.font(.system(size: 9)).monospacedDigit().foregroundStyle(.white.opacity(0.35))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback progress")
            .accessibilityValue("\(MediaProgressView.time(elapsed)) of \(duration.map(MediaProgressView.time) ?? "unknown duration")")
        }
    }
}
