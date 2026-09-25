import SwiftUI

/// All presentation properties are interpolated by this single SwiftUI animation.
/// The content closure receives presentation progress, not the model's target state.
nonisolated struct NotchTransitionSurface<Content: View>: View, Animatable {
    var progress: CGFloat
    var shape: NotchShellSurface
    let expandedSize: CGSize
    let isTransitioning: Bool
    @ViewBuilder var content: @MainActor (NotchContentMotion) -> Content

    var animatableData: AnimatablePair<CGFloat, NotchShellSurface.AnimatableData> {
        get { AnimatablePair(progress, shape.animatableData) }
        set {
            progress = newValue.first
            shape.animatableData = newValue.second
        }
    }

    @MainActor var body: some View {
        let motion = NotchContentMotion(progress: progress, expandedWidth: expandedSize.width)
        content(motion)
            .environment(\.notchContentMotion, motion)
            .environment(\.notchShellIsTransitioning, isTransitioning || motion.isInFlight)
            .background { shape.fill(.black).allowsHitTesting(false) }
            .mask(shape)
            // The vector above already interpolated shell and content geometry. A second
            // implicit animation here would make layout, artwork or metadata lag behind it.
            .transaction { transaction in
                if isTransitioning || motion.isInFlight {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
    }
}

struct NotchContentMotion: Equatable, Sendable {
    var progress: CGFloat = 1
    var expandedWidth: CGFloat = 524

    var isInFlight: Bool { progress > 0 && progress < 1 }
    // Swap only within ~6 points of the collapsed shell's final dimensions.
    var showsExpanded: Bool { progress > 0.025 }

    /// Move each fixed-size component toward the top center. Its bottom edge ends
    /// above the mask, so the collapsed rendering never inherits expanded artwork.
    func offset(for frame: CGRect) -> CGSize {
        let remaining = 1 - min(1, max(0, progress))
        return CGSize(
            width: (expandedWidth / 2 - frame.midX) * remaining,
            height: (-frame.maxY - 1) * remaining
        )
    }
}

extension EnvironmentValues {
    @Entry var notchContentMotion = NotchContentMotion()
    @Entry public var notchShellIsTransitioning = false
}

/// Geometry-only visibility; both presentations stay mounted through reversals.
/// An empty clip is intentional: hidden() or conditional insertion would rebuild content.
struct NotchPresentationClip: ViewModifier {
    let visible: Bool

    func body(content: Content) -> some View {
        content.mask(alignment: .top) {
            Rectangle().frame(maxHeight: visible ? .infinity : 0)
        }
    }
}

private struct NotchRetractingContent: ViewModifier {
    @Environment(\.notchContentMotion) private var motion

    func body(content: Content) -> some View {
        let motion = motion
        return content.visualEffect { effect, geometry in
            let offset = motion.offset(for: geometry.frame(in: .named("notch.expandedContent")))
            return effect.offset(x: offset.width, y: offset.height)
        }
    }
}

extension View {
    /// Apply once to a fixed-layout component (or group), never to both parent and child.
    func notchRetractingContent() -> some View {
        modifier(NotchRetractingContent())
    }
}
