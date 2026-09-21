import SwiftUI
import NotchiumServices
import NotchiumDynamicIsland

struct MediaProgressView: View {
    let model: MediaFeatureModel
    @State private var isSeeking = false
    @State private var seekPosition = 0.0
    @Environment(\.notchMediaExpanded) private var isVisible

    var body: some View {
        TimelineView(.animation(minimumInterval: model.state.isPlaying ? 0.1 : nil,
                                paused: !model.state.isPlaying || !isVisible || isSeeking)) { timeline in
            let position = mediaSliderDisplayPosition(
                isSeeking: isSeeking,
                seekPosition: seekPosition,
                estimatedPosition: model.displayedPosition(at: timeline.date)
            )
            VStack(spacing: 2) {
                NotchiumSlider(
                    value: Binding(get: { position }, set: { seekPosition = $0 }),
                    in: 0...max(1, model.state.validDuration ?? 1),
                    accessibilityLabel: "Seek",
                    accessibilityStep: 5,
                    accessibilityValue: Self.time
                ) { editing in
                    if editing {
                        isSeeking = true
                        seekPosition = model.displayedPosition(at: timeline.date)
                    } else {
                        #if DEBUG
                        print("[MediaControl] SEEK tapped")
                        #endif
                        let target = seekPosition
                        model.send(.seek(target))
                        seekPosition = target
                        isSeeking = false
                    }
                }
                .frame(height: 20)
                .disabled(!model.state.canSeek || (model.isPending(.seek(0)) && !isSeeking))
                HStack {
                    Text(Self.time(position))
                    Spacer()
                    Text(model.state.validDuration.map(Self.time) ?? "–:––")
                }
                .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.gray)
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
}

func mediaSliderDisplayPosition(isSeeking: Bool, seekPosition: Double,
                                estimatedPosition: Double) -> Double {
    isSeeking ? seekPosition : estimatedPosition
}
