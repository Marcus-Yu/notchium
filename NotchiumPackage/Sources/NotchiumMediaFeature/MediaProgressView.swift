import SwiftUI
import NotchiumServices
import NotchiumDynamicIsland

struct MediaProgressView: View {
    let model: MediaFeatureModel
    @State private var isDragging = false
    @State private var draggedPosition = 0.0
    @Environment(\.notchMediaExpanded) private var isVisible

    var body: some View {
        TimelineView(.animation(minimumInterval: model.state.isPlaying ? 0.1 : nil,
                                paused: !model.state.isPlaying || !isVisible || isDragging)) { timeline in
            let position = isDragging ? draggedPosition : model.displayedPosition(at: timeline.date)
            VStack(spacing: 2) {
                Slider(value: Binding(get: { position }, set: { draggedPosition = $0 }),
                       in: 0...max(1, model.state.validDuration ?? 1)) { Text("Seek") }
                onEditingChanged: { editing in
                    if editing {
                        draggedPosition = model.displayedPosition(at: timeline.date)
                        isDragging = true
                    } else {
                        #if DEBUG
                        print("[MediaControl] SEEK tapped")
                        #endif
                        model.seek(to: draggedPosition)
                        isDragging = false
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
                            Capsule().fill(.white.opacity(0.22)).frame(width: width, height: 3)
                            Capsule().fill(.white).frame(width: width * fraction, height: 3)
                            Circle().fill(.white).frame(width: 8, height: 8)
                                .offset(x: width * fraction - 4)
                        }
                        .frame(height: 12).padding(.horizontal, 6)
                    }
                    .background(.black)
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
                .disabled(!model.state.canSeek || (model.isPending(.seek(0)) && !isDragging))
                .accessibilityValue(Self.time(position))
                HStack {
                    Text(Self.time(position))
                    Spacer()
                    Text(model.state.validDuration.map(Self.time) ?? "–:––")
                }
                .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.gray)
            }
            // A transport update must never implicitly animate the slider backward through a track change.
            .transaction { $0.animation = nil }
        }
        .onChange(of: model.state) { old, new in
            if !new.isSameTrack(as: old) || !new.hasMedia { isDragging = false }
        }
    }
    private static func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(min(max(0, seconds), 86_400)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
