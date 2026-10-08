import SwiftUI
import NotchiumDesignSystem
import NotchiumServices
import NotchiumDynamicIsland

struct MediaProgressView: View {
    let model: MediaFeatureModel
    @State private var isSeeking = false
    @State private var seekPosition = 0.0
    @Environment(\.notchMediaExpanded) private var isExpanded

    var body: some View {
        TimelineView(.animation(minimumInterval: model.state.isPlaying ? 0.1 : nil,
                                paused: !model.state.isPlaying || !isExpanded || isSeeking)) { timeline in
            let position = mediaSliderDisplayPosition(
                isSeeking: isSeeking,
                seekPosition: seekPosition,
                estimatedPosition: model.displayedPosition(at: timeline.date, uptime: ProcessInfo.processInfo.systemUptime)
            )
            VStack(spacing: 2) {
                NotchiumSlider(
                    value: Binding(get: { position }, set: { seekPosition = $0 }),
                    in: 0...max(1, model.state.validDuration ?? 1),
                    accessibilityLabel: "Playback position",
                    accessibilityStep: 5,
                    accessibilityValue: { Self.spokenPosition($0, duration: model.state.validDuration) }
                ) { editing in
                    if editing {
                        isSeeking = true
                        seekPosition = model.displayedPosition(at: timeline.date, uptime: ProcessInfo.processInfo.systemUptime)
                    } else {
                        guard isSeeking else { return }
                        let target = seekPosition
                        model.send(.seek(target))
                        seekPosition = target
                        isSeeking = false
                    }
                }
                .frame(height: 20)
                .disabled(!model.state.canSeek)
                HStack {
                    Text(Self.time(position))
                    Spacer()
                    Text(model.state.validDuration.map(Self.time) ?? "–:––")
                }
                .font(.system(size: 10.5, weight: .medium)).monospacedDigit().foregroundStyle(.gray)
            }
        }
        .onChange(of: model.state) { old, new in
            if !new.isSameTrack(as: old) || !new.hasMedia { isSeeking = false }
        }
    }
    static func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(min(max(0, seconds), 86_400)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    static func spokenPosition(_ elapsed: Double, duration: Double?) -> String {
        let elapsedText = "Elapsed \(spokenTime(elapsed))"
        guard let duration, duration.isFinite, duration > 0 else { return elapsedText }
        return "\(elapsedText) of \(spokenTime(duration))"
    }

    private static func spokenTime(_ seconds: Double) -> String {
        let totalSeconds = seconds.isFinite ? Int(min(max(0, seconds), 86_400)) : 0
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if remainingSeconds > 0 || parts.isEmpty {
            parts.append("\(remainingSeconds) second\(remainingSeconds == 1 ? "" : "s")")
        }
        return parts.joined(separator: " ")
    }
}

func mediaSliderDisplayPosition(isSeeking: Bool, seekPosition: Double,
                                estimatedPosition: Double) -> Double {
    isSeeking ? seekPosition : estimatedPosition
}
