import Foundation

/// Continuous product yaw, independent of banner expiry. Callers supply monotonic time;
/// sampling never mutates state or schedules work.
struct NotchAirPodsMotion {
    static let turnDuration = 1.2
    /// Retain the original turn's gentle acceleration, then cruise without a pause at the seam.
    static let velocityTransitionDuration = 0.22

    struct Sample {
        let phase: Double
        let velocity: Double
    }

    private var anchor: ContinuousClock.Instant
    private var phase = 0.0
    private var velocity = 0.0
    private var targetVelocity: Double

    init(connected: Bool, at instant: ContinuousClock.Instant) {
        anchor = instant
        targetVelocity = Self.speed(connected: connected)
    }

    mutating func setConnected(_ connected: Bool, at instant: ContinuousClock.Instant) {
        let target = Self.speed(connected: connected)
        // Route/battery updates in the same direction must not restart acceleration.
        guard target != targetVelocity else { return }
        let current = sample(at: instant)
        anchor = instant
        phase = current.phase
        velocity = current.velocity
        targetVelocity = target
    }

    func sample(at instant: ContinuousClock.Instant) -> Sample {
        let elapsed = max(0, anchor.duration(to: instant) / .seconds(1))
        let duration = Self.velocityTransitionDuration
        let rampTime = min(elapsed, duration)
        let t = rampTime / duration
        let delta = targetVelocity - velocity
        // Integrate smoothstep velocity so both pose and speed survive an interruption.
        let rampDistance = velocity * rampTime + delta * duration * (t * t * t - t * t * t * t / 2)
        return Sample(phase: phase + rampDistance + targetVelocity * max(0, elapsed - duration),
                      velocity: velocity + delta * t * t * (3 - 2 * t))
    }

    static func pose(at phase: Double) -> Double {
        guard phase.isFinite else { return 0 }
        let nearest = phase.rounded()
        let canonical = abs(phase - nearest) < 1e-9 ? nearest : phase
        return canonical - canonical.rounded(.down)
    }

    private static func speed(connected: Bool) -> Double {
        (connected ? 1.0 : -1.0) / turnDuration
    }
}
