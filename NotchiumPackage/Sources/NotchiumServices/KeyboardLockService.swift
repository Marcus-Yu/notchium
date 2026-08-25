import NotchiumCore

public struct KeyboardLockPolicy: Equatable, Sendable {
    public let emergencyChord: String
    public let emergencyHoldDuration: Duration
    public let mouseRemainsUsable: Bool
    public let unlockOnTapFailure: Bool

    public init(
        emergencyChord: String,
        emergencyHoldDuration: Duration,
        mouseRemainsUsable: Bool,
        unlockOnTapFailure: Bool
    ) {
        self.emergencyChord = emergencyChord
        self.emergencyHoldDuration = emergencyHoldDuration
        self.mouseRemainsUsable = mouseRemainsUsable
        self.unlockOnTapFailure = unlockOnTapFailure
    }

    public static let productDefault = KeyboardLockPolicy(
        emergencyChord: "Control–Option–Command–Escape",
        emergencyHoldDuration: .seconds(3),
        mouseRemainsUsable: true,
        unlockOnTapFailure: true
    )
}

public struct KeyboardLockSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let isLocked: Bool

    public init(availability: FeatureAvailability, isLocked: Bool = false) {
        self.availability = availability
        self.isLocked = isLocked
    }
}

public protocol KeyboardLockService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<KeyboardLockSnapshot>
    func lock(policy: KeyboardLockPolicy) async throws
    func unlock() async
}

public struct RealKeyboardLockService: KeyboardLockService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.keyboardLock)
    }

    public func updates() async -> AsyncStream<KeyboardLockSnapshot> {
        oneShotStream(KeyboardLockSnapshot(availability: stageOneUnavailable(.keyboardLock)))
    }

    public func lock(policy: KeyboardLockPolicy) async throws {
        throw ServiceFailure.stageTwoRequired(.keyboardLock)
    }

    public func unlock() async {}
}

public struct MockKeyboardLockService: KeyboardLockService {
    public let snapshot: KeyboardLockSnapshot

    public init(
        snapshot: KeyboardLockSnapshot = KeyboardLockSnapshot(availability: .available)
    ) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<KeyboardLockSnapshot> {
        oneShotStream(snapshot)
    }

    public func lock(policy: KeyboardLockPolicy) async throws {}
    public func unlock() async {}
}
