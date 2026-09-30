import NotchiumServices

/// Turns event-driven battery snapshots into at most one transient per meaningful change.
/// Every event maps to the single "battery" activity identity, so severity changes update it.
///
/// - Charger connected/disconnected: one short event per actual transition.
/// - Low (20%) and critical (10%): each announced once when crossed while discharging, never
///   at launch. A threshold re-arms only after meaningful recovery (charging, or rising
///   `rearmMargin` above it), so fluctuation around a threshold cannot nag.
struct BatteryActivityPolicy {
    enum Event: Equatable {
        case charging(level: Double)
        case powerDisconnected(level: Double)
        case low(level: Double)
        case critical(level: Double)
    }

    static let lowThreshold = 0.20
    static let criticalThreshold = 0.10
    static let rearmMargin = 0.05

    private var previous: BatterySnapshot?
    private var lowArmed = true
    private var criticalArmed = true

    mutating func receive(_ snapshot: BatterySnapshot) -> Event? {
        guard snapshot.availability == .available, let level = snapshot.chargeLevel else { return nil }
        defer { previous = snapshot }
        guard let previous else {
            // The state at launch is already known to the user: arm only thresholds still above.
            lowArmed = level > Self.lowThreshold
            criticalArmed = level > Self.criticalThreshold
            return nil
        }
        if snapshot.isConnectedToPower != previous.isConnectedToPower {
            if snapshot.isConnectedToPower {
                lowArmed = true
                criticalArmed = true
                return .charging(level: level)
            }
            // Unplugging below a threshold is not a new crossing; the user just made the choice.
            lowArmed = level > Self.lowThreshold
            criticalArmed = level > Self.criticalThreshold
            return .powerDisconnected(level: level)
        }
        if level >= Self.lowThreshold + Self.rearmMargin { lowArmed = true }
        if level >= Self.criticalThreshold + Self.rearmMargin { criticalArmed = true }
        guard !snapshot.isConnectedToPower else { return nil }
        if criticalArmed, level <= Self.criticalThreshold {
            criticalArmed = false
            lowArmed = false
            return .critical(level: level)
        }
        if lowArmed, level <= Self.lowThreshold {
            lowArmed = false
            return .low(level: level)
        }
        return nil
    }
}
