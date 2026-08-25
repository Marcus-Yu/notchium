import NotchCore

public struct BatterySnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let chargeLevel: Double?
    public let isCharging: Bool
    public let isConnectedToPower: Bool

    public init(
        availability: FeatureAvailability,
        chargeLevel: Double? = nil,
        isCharging: Bool = false,
        isConnectedToPower: Bool = false
    ) {
        self.availability = availability
        self.chargeLevel = chargeLevel
        self.isCharging = isCharging
        self.isConnectedToPower = isConnectedToPower
    }
}

public protocol BatteryService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<BatterySnapshot>
}

public struct RealBatteryService: BatteryService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.battery)
    }

    public func updates() async -> AsyncStream<BatterySnapshot> {
        oneShotStream(BatterySnapshot(availability: stageOneUnavailable(.battery)))
    }
}

public struct MockBatteryService: BatteryService {
    public let snapshot: BatterySnapshot

    public init(snapshot: BatterySnapshot = BatterySnapshot(availability: .available)) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<BatterySnapshot> {
        oneShotStream(snapshot)
    }
}
