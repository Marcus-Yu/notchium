import Foundation
import IOKit.ps
import NotchiumCore

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

/// Internal-battery state from IOKit's public power-source API. Changes arrive through
/// IOPSNotificationCreateRunLoopSource on the main run loop; nothing polls.
@MainActor
public final class RealBatteryService: BatteryService {
    private var continuations: [UUID: AsyncStream<BatterySnapshot>.Continuation] = [:]
    private var source: CFRunLoopSource?

    nonisolated public init() {}

    isolated deinit { stopObservation() }

    public func availability() async -> FeatureAvailability {
        Self.read().availability
    }

    public func updates() async -> AsyncStream<BatterySnapshot> {
        let id = UUID()
        let pair = AsyncStream<BatterySnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.remove(id) }
        }
        startIfNeeded()
        pair.continuation.yield(Self.read())
        return pair.stream
    }

    private func startIfNeeded() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        // A C callback cannot capture: the service is recovered from the context pointer.
        // The source lives on the main run loop, so the callback runs on the main thread.
        guard let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<RealBatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.publish() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
        source = created
    }

    private func publish() {
        let snapshot = Self.read()
        continuations.values.forEach { $0.yield(snapshot) }
    }

    private func remove(_ id: UUID) {
        continuations.removeValue(forKey: id)
        guard continuations.isEmpty else { return }
        stopObservation()
    }

    private func stopObservation() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        CFRunLoopSourceInvalidate(source)
        self.source = nil
    }

    static func read() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatterySnapshot(availability: .unavailable(.unsupportedHardware))
        }
        for powerSource in list {
            guard let description = IOPSGetPowerSourceDescription(info, powerSource)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return BatterySnapshot(
                availability: .available,
                chargeLevel: min(max(Double(current) / Double(maximum), 0), 1),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isConnectedToPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }
        // Desktop Macs have no internal battery.
        return BatterySnapshot(availability: .unavailable(.unsupportedHardware))
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
