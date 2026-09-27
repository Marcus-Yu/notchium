import SwiftUI

/// Visual lifetime is independent of interaction state and its hover bookkeeping.
struct NotchVisualTransition: Equatable {
    enum Phase: Equatable { case collapsed, openingBlack, expanded, closingBlack }
    private(set) var phase: Phase
    private(set) var generation = 0

    init(expanded: Bool) { phase = expanded ? .expanded : .collapsed }

    mutating func begin(expanded: Bool) -> Int {
        generation &+= 1
        phase = expanded ? .openingBlack : .closingBlack
        return generation
    }

    mutating func complete(generation: Int) {
        guard generation == self.generation else { return }
        switch phase {
        case .openingBlack: phase = .expanded
        case .closingBlack: phase = .collapsed
        default: break
        }
    }

    var isBlack: Bool { phase == .openingBlack || phase == .closingBlack }
}

/// The persistent shell alone owns animated geometry. Both content trees retain
/// their normal layout and identity, with visibility changed without animation.
struct NotchTransitionSurface<Content: View>: View {
    let expanded: Bool
    let shape: NotchShellSurface
    let reduceMotion: Bool
    let notificationVisible: Bool
    var retainsMedia = false
    @State private var wasNotificationVisible: Bool
    @State private var preservesNotificationContent = false
    @State private var wasExpanded: Bool
    @State private var isNotificationTransition = false
    @ViewBuilder var content: @MainActor (NotchVisualTransition.Phase) -> Content
    @State private var renderedShape: NotchShellSurface
    @State private var transition: NotchVisualTransition

    init(expanded: Bool, shape: NotchShellSurface, reduceMotion: Bool, notificationVisible: Bool = false,
         retainsMedia: Bool = false,
         @ViewBuilder content: @escaping @MainActor (NotchVisualTransition.Phase) -> Content) {
        self.expanded = expanded
        self.shape = shape
        self.reduceMotion = reduceMotion
        self.notificationVisible = notificationVisible
        self.retainsMedia = retainsMedia
        _wasNotificationVisible = State(initialValue: notificationVisible)
        _wasExpanded = State(initialValue: expanded)
        self.content = content
        _renderedShape = State(initialValue: shape)
        _transition = State(initialValue: NotchVisualTransition(expanded: expanded))
    }

    var body: some View {
        // Hide in the very first target-state update, before onChange retargets the
        // geometry. This also prevents a stale completion flashing on reversal.
        let targetChanged = renderedShape.animatableData != shape.animatableData
        NotchSurfaceFrame(
            shape: renderedShape,
            phase: transition.phase,
            expandedHeight: shape.height,
            hidesPendingTarget: targetChanged && !(notificationVisible && wasNotificationVisible && !expanded && !wasExpanded),
            notificationVisible: notificationVisible,
            keepsNotificationContent: preservesNotificationContent,
            preservesCollapsedMedia: retainsMedia && !expanded
                && (targetChanged ? !wasExpanded : (isNotificationTransition || !transition.isBlack)),
            content: content
        )
        .onChange(of: shape.animatableData) { _, _ in retarget() }
    }

    private func retarget() {
        preservesNotificationContent = notificationVisible && wasNotificationVisible && !expanded && !wasExpanded
        let notificationMotion = !expanded && !wasExpanded && (notificationVisible || wasNotificationVisible)
        isNotificationTransition = notificationMotion
        let generation = transition.begin(expanded: expanded || notificationVisible)
        let animation = notificationMotion
            ? (notificationVisible ? NotchMotion.notificationIn : NotchMotion.notificationOut)
            : NotchMotion.shell
        wasExpanded = expanded
        wasNotificationVisible = notificationVisible
        // Only this shape receives the animation. A reversal retargets the same
        // SwiftUI spring from its live presentation position and velocity.
        withAnimation(reduceMotion ? NotchMotion.reduced : animation,
                      completionCriteria: .removed) {
            renderedShape = shape
        } completion: {
            transition.complete(generation: generation)
        }
    }
}

/// Interpolates only shell geometry. The content gate reads that presentation
/// geometry directly, without timers or per-frame observable-state writes.
nonisolated struct NotchSurfaceFrame<Content: View>: View, Animatable {
    var shape: NotchShellSurface
    let phase: NotchVisualTransition.Phase
    let expandedHeight: CGFloat
    var hidesPendingTarget = false
    var notificationVisible = false
    var keepsNotificationContent = false
    var preservesCollapsedMedia = false
    @ViewBuilder var content: @MainActor (NotchVisualTransition.Phase) -> Content

    var animatableData: NotchShellSurface.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }

    var contentPhase: NotchVisualTransition.Phase {
        guard !hidesPendingTarget else { return .closingBlack }
        if notificationVisible && keepsNotificationContent { return .collapsed }
        if notificationVisible && phase == .expanded { return .collapsed }
        if phase == .openingBlack {
            let collapsedHeight = shape.passiveShape.height
            let revealHeight = collapsedHeight + (expandedHeight - collapsedHeight) * 0.75
            return shape.height >= revealHeight ? (notificationVisible ? .collapsed : .expanded) : .openingBlack
        }
        return phase
    }

    @MainActor var body: some View {
        let visible = contentPhase == .expanded || contentPhase == .collapsed
        let transitioning = phase == .openingBlack || phase == .closingBlack || hidesPendingTarget
        ZStack(alignment: .top) {
            shape.fill(.black).allowsHitTesting(false)
            content(contentPhase)
                .modifier(NotchPresentationClip(visible: visible || preservesCollapsedMedia))
                .mask(shape)
                .environment(\.notchPreservesCollapsedMedia, preservesCollapsedMedia)
                .environment(\.notchShellIsTransitioning, transitioning)
                // Notification input can reverse entry before its content reveal
                // finishes; main expand/collapse keeps the established black gate.
                .allowsHitTesting(visible || notificationVisible || preservesCollapsedMedia)
                .accessibilityHidden(!visible && !preservesCollapsedMedia)
        }
        // This wrapper has already interpolated geometry. Neither its shape nor
        // the fixed-size content should start a second animation on each sample.
        .transaction { transaction in
            if transitioning {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}

extension EnvironmentValues {
    @Entry public var notchShellIsTransitioning = false
    @Entry var notchPreservesCollapsedMedia = false
}

struct CollapsedMediaPresentation: ViewModifier {
    let visible: Bool
    @Environment(\.notchPreservesCollapsedMedia) private var preservesMedia

    func body(content: Content) -> some View {
        content.modifier(NotchPresentationClip(visible: visible || preservesMedia))
    }
}

/// Binary visibility, with no insertion/removal, fade, scale or layout mutation.
struct NotchPresentationClip: ViewModifier {
    let visible: Bool

    func body(content: Content) -> some View {
        content.mask {
            Rectangle().opacity(visible ? 1 : 0)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
        }
    }
}
