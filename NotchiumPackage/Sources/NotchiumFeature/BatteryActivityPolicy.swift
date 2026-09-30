import NotchiumServices

/// Turns battery snapshots into at most one transient activity per meaningful change:
/// plugging in, and each low threshold crossed once per discharge (never at launch).
struct BatteryActivityPolicy {
    enum Event: Equatable {
        case charging(level: Double)
        case low(level: Double)
    }

    static let lowThresholds: [Double] = [0.20, 0.10]
    private var previous: BatterySnapshot?
    private var announced: Set<Double> = []

    mutating func receive(_ snapshot: BatterySnapshot) -> Event? {
        defer { previous = snapshot }
        guard snapshot.availability == .available, let level = snapshot.chargeLevel else { return nil }
        let crossed = Set(Self.lowThresholds.filter { level <= $0 })
        guard let previous, previous.availability == .available else {
            // The state at launch is already known to the user.
            if !snapshot.isConnectedToPower { announced = crossed }
            return nil
        }
        if snapshot.isConnectedToPower {
            announced.removeAll()
            return previous.isConnectedToPower ? nil : .charging(level: level)
        }
        guard !crossed.isSubset(of: announced) else { return nil }
        announced.formUnion(crossed)
        return .low(level: level)
    }
}
