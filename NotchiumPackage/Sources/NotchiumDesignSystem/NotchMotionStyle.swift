import SwiftUI

/// Shared timing for small controls and content that changes inside a stable notch surface.
/// Shell geometry owns its separate spring; live pointer and playback coordinates stay direct.
public enum NotchMotionStyle {
    public static let reduced = Animation.easeOut(duration: 0.1)

    public static func feedback(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .smooth(duration: 0.16)
    }

    public static func contentChange(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .smooth(duration: 0.22)
    }

    /// A selection that moves between siblings (the header pill, a segmented choice): quick, with
    /// the faint settle that makes the Dynamic Island feel physical.
    public static func selection(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .spring(response: 0.32, dampingFraction: 0.78)
    }
}

/// How far the expanded content has grown out of the notch. The shell writes this every frame
/// from its own interpolated geometry, so content reveals ride the shell spring: they reverse
/// with it and need no timer. 1 whenever the shell is settled open.
public struct NotchBloomProgress: Equatable, Sendable {
    /// 0 at the collapsed notch, 1 at the full expanded height.
    public var progress: CGFloat
    /// Closing dissolves content early and without stagger; opening blooms it in late and staggered.
    public var closing: Bool

    public init(progress: CGFloat, closing: Bool) {
        self.progress = progress
        self.closing = closing
    }

    public static let settled = NotchBloomProgress(progress: 1, closing: false)
    public static let hidden = NotchBloomProgress(progress: 0, closing: false)

    /// The eased visibility (0...1) of one reveal stage. Stage 0 is the header row,
    /// later stages are the content beneath it.
    public func amount(stage: Int) -> CGFloat {
        let start: CGFloat
        let end: CGFloat
        if closing {
            start = 0.5
            end = 0.9
        } else {
            start = 0.26 + CGFloat(max(0, stage)) * 0.1
            end = start + 0.46
        }
        let t = min(max((progress - start) / (end - start), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

public extension EnvironmentValues {
    @Entry var notchBloom = NotchBloomProgress.settled
}

/// Content that grows out of the notch: it sharpens from a blur, fades up and settles from a
/// slightly smaller, raised position. Reduce Motion keeps only the fade.
public struct NotchBloom: ViewModifier {
    let stage: Int
    @Environment(\.notchBloom) private var bloom
    @NotchReducedMotion private var reduceMotion

    public init(stage: Int) { self.stage = stage }

    public func body(content: Content) -> some View {
        let amount = bloom.amount(stage: stage)
        // One modifier chain with identity values at rest: branching here would replace the
        // page's view identity (and its state, tasks and AppKit views) when the bloom completes.
        // Fully hidden content (the collapsed notch, most of the time) carries no blur either,
        // so an invisible page never costs a filter pass.
        let remaining = reduceMotion || amount <= 0 ? 0 : 1 - amount
        content
            // A mask, not `.opacity`: Liquid Glass inside the page (utility hover glass, slider
            // thumbs) renders through ancestor opacity, and would ghost on the collapsed notch.
            // Unbounded, so it never clips content that overflows its frame (header hover
            // labels, the Caffeine time tag); the shell's shape does the spatial clipping.
            .mask { Rectangle().opacity(amount).padding(-1_000) }
            .blur(radius: 9 * remaining)
            .scaleEffect(1 - 0.06 * remaining, anchor: .top)
            .offset(y: -8 * remaining)
    }
}

public extension View {
    /// Joins the shell's bloom; see `NotchBloom`.
    func notchBloom(stage: Int) -> some View { modifier(NotchBloom(stage: stage)) }
}
