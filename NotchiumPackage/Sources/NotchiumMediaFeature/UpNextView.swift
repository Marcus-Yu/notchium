import NotchiumDesignSystem
import NotchiumServices
import SwiftUI

struct UpNextView: View {
    let state: MediaState

    var body: some View {
        Group {
            if state.queueIssue != nil || !state.capabilities.canReadQueue {
                queueMessage("Queue unavailable", detail: "Open Spotify to see what’s next.")
            } else if state.queue.isEmpty {
                queueMessage("Nothing queued", detail: "Add songs to your queue in Spotify.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.queue) { track in
                            QueueTrackRow(track: track)
                        }
                    }
                }
                .contentMargins(.trailing, 20, for: .scrollContent)
                .scrollIndicators(.visible, axes: .vertical)
                .scrollIndicatorsFlash(onAppear: true)
                .environment(\.colorScheme, .dark)
                .accessibilityLabel("Upcoming songs")
            }
        }
        .padding(.top, ExpandedPageStyle.Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .accessibilityIdentifier("notchium.media.up-next")
    }

    private func queueMessage(_ title: String, detail: String) -> some View {
        VStack(spacing: ExpandedPageStyle.Space.xs) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 18))
                .foregroundStyle(ExpandedPageStyle.secondary)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(ExpandedPageStyle.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QueueTrackRow: View {
    let track: QueueTrack

    var body: some View {
        HStack(spacing: ExpandedPageStyle.Space.sm) {
            MediaArtwork(url: track.artworkURL, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(track.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(ExpandedPageStyle.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if track.duration.isFinite, track.duration > 0 {
                Text(duration)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(ExpandedPageStyle.secondary)
                    .fixedSize()
            }
        }
        .frame(height: 44)
        .help("\(track.title) — \(track.artist)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(track.title), \(track.artist)")
        .accessibilityValue(track.duration.isFinite && track.duration > 0 ? duration : "")
        .accessibilityIdentifier("notchium.media.queue.\(track.id)")
    }

    private var duration: String {
        let seconds = Int(min(max(track.duration, 0), 86_400))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
