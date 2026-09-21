import SwiftUI
import NotchiumServices
import NotchiumDynamicIsland

struct MediaProgressView: View {
    let model: MediaFeatureModel
    @State private var isSeeking = false
    @State private var isHovered = false
    @State private var seekPosition = 0.0
    @Environment(\.notchMediaExpanded) private var isVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: model.state.isPlaying ? 0.1 : nil,
                                paused: !model.state.isPlaying || !isVisible || isSeeking)) { timeline in
            let position = mediaSliderDisplayPosition(
                isSeeking: isSeeking,
                seekPosition: seekPosition,
                estimatedPosition: model.displayedPosition(at: timeline.date)
            )
            VStack(spacing: 2) {
                Slider(value: Binding(get: { position }, set: { seekPosition = $0 }),
                       in: 0...max(1, model.state.validDuration ?? 1)) { Text("Seek") }
                onEditingChanged: { editing in
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
                .labelsHidden().controlSize(.mini).tint(.white)
                .frame(height: 12)
                .overlay {
                    // Keep native pointer/keyboard/accessibility behavior, with a legible black-surface track.
                    GeometryReader { proxy in
                        let width = max(0, proxy.size.width - 12)
                        let fraction = model.state.validDuration.map { min(max(position / $0, 0), 1) } ?? 0
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(isHovered || isSeeking ? 0.28 : 0.2))
                                .frame(width: width, height: isSeeking ? 4 : 3)
                            Capsule()
                                .fill(.white.opacity(isHovered || isSeeking ? 1 : 0.9))
                                .frame(width: width * fraction, height: isSeeking ? 4 : 3)
                            Circle()
                                .fill(.white)
                                .frame(width: 9, height: 9)
                                .glassEffect(.clear, in: .circle)
                                .scaleEffect(isSeeking ? 1.22 : isHovered ? 1.1 : 1)
                                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                                .offset(x: width * fraction - 4.5)
                        }
                        .frame(height: 14)
                        .padding(.horizontal, 6)
                        .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.16),
                                   value: isHovered)
                        .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.16),
                                   value: isSeeking)
                    }
                    .background(.black)
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
                .contentShape(.rect)
                .onHover { isHovered = $0 }
                .disabled(!model.state.canSeek || (model.isPending(.seek(0)) && !isSeeking))
                .accessibilityValue(Self.time(position))
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
    private static func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(min(max(0, seconds), 86_400)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

func mediaSliderDisplayPosition(isSeeking: Bool, seekPosition: Double,
                                estimatedPosition: Double) -> Double {
    isSeeking ? seekPosition : estimatedPosition
}
