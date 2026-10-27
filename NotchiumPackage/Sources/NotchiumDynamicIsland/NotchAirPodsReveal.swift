import Foundation

/// Shared entry/exit choreography sampled from the shell's reveal. Reversals use the same
/// presentation values, so an interrupted reveal never jumps onto a different exit curve.
struct NotchAirPodsReveal {
    let leadingInset: CGFloat
    let scale: CGFloat
    let opacity: Double

    init(reveal: CGFloat, sideWidth: CGFloat, restoresMedia: Bool) {
        // Finish before the hardware mask closes, or before Music reclaims the leading slot.
        let retentionBoundary: CGFloat = restoresMedia ? 1 / 3 : 0
        let hiddenAt = retentionBoundary + (1 - retentionBoundary) * 0.12
        let travel = min(max((1 - reveal) / (1 - hiddenAt), 0), 1)
        let eased = travel * travel * (3 - 2 * travel)
        leadingInset = sideWidth * travel
        scale = 1 - 0.28 * eased
        // Let the inward movement read first, then disappear softly beneath the notch.
        let fade = min(max((travel - 0.15) / 0.85, 0), 1)
        opacity = Double(1 - fade * fade * (3 - 2 * fade))
    }
}
