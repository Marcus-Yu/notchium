import Foundation
import NotchiumDynamicIsland
import NotchiumServices

/// One normalized model for every output device: AirPods, headphones, speakers, displays.
/// Hardware truth stays in AudioDevicesService; this is the feature's presentation projection.
public struct OutputDeviceState: Identifiable, Equatable, Sendable {
    public enum Battery: Equatable, Sendable {
        /// macOS offers no supported API for this device's battery.
        case unsupported
        /// No current reading (never reported, empty, or stale).
        case unavailable
        case available(DeviceBatteryLevels)
    }

    /// Readings older than this are not presented as live.
    static let batteryMaxAge: TimeInterval = 5 * 60

    /// Stable across reconnects (Core Audio UID); falls back to the connection's object ID.
    public let id: String
    public let objectID: String
    public let name: String
    public let category: NotchDeviceStyle
    public let isActiveOutput: Bool
    public let battery: Battery

    public init(_ device: AudioDevice, now: Date) {
        id = device.uid ?? device.id
        objectID = device.id
        name = device.name
        category = .classify(name: device.name,
                             transport: NotchAudioTransport(rawValue: device.transport.rawValue) ?? .other)
        isActiveOutput = device.isDefaultOutput
        battery = switch device.battery {
        case .unsupported: .unsupported
        case .unavailable: .unavailable
        case let .available(levels): Self.isPresentable(levels, now: now) ? .available(levels) : .unavailable
        }
    }

    /// Wearables announce connect/disconnect even when they do not take the route.
    var isWearable: Bool { category.spinsOnConnect }

    /// The compact notch shows one level: the source's single value, else the lower bud.
    /// Case level never stands in for the buds, and nothing is shown without a reading.
    public var aggregateBattery: NotchDeviceBattery? {
        guard case let .available(levels) = battery,
              let level = levels.single ?? [levels.left, levels.right].compactMap({ $0 }).min() else { return nil }
        return NotchDeviceBattery(level: min(max(level, 0), 1), isCharging: levels.isCharging ?? false)
    }

    private static func isPresentable(_ levels: DeviceBatteryLevels, now: Date) -> Bool {
        let age = now.timeIntervalSince(levels.measuredAt)
        let hasValue = [levels.single, levels.left, levels.right, levels.caseLevel].contains { $0 != nil }
        return hasValue && age >= -60 && age <= batteryMaxAge
    }
}

/// Normalizes Core Audio's separate device-list and default-output callbacks into at most one
/// transition per snapshot. Connect and switch present identically, so "device appeared" followed
/// by "became default" coalesces into one unchanged activity instead of two.
enum OutputDeviceTransition: Equatable {
    case connected(OutputDeviceState)
    case disconnected(OutputDeviceState)

    static func between(_ old: [OutputDeviceState], _ new: [OutputDeviceState]) -> Self? {
        let oldIDs = Set(old.map(\.id)), newIDs = Set(new.map(\.id))
        let oldActive = old.first(where: \.isActiveOutput)
        let newActive = new.first(where: \.isActiveOutput)
        if newActive?.id != oldActive?.id {
            // The newest route wins; a vanished active device is announced only if nothing new arrived.
            if let newActive, !oldIDs.contains(newActive.id) { return .connected(newActive) }
            if let oldActive, !newIDs.contains(oldActive.id) { return .disconnected(oldActive) }
            return newActive.map { .connected($0) }
        }
        if let appeared = new.first(where: { $0.isWearable && !oldIDs.contains($0.id) }) { return .connected(appeared) }
        if let left = old.first(where: { $0.isWearable && !newIDs.contains($0.id) }) { return .disconnected(left) }
        return nil
    }

    var hud: NotchAudioHUD {
        switch self {
        case let .connected(device):
            NotchAudioHUD(kind: .outputChanged, deviceName: device.name, volume: nil, isMuted: false,
                          deviceStyle: device.category, deviceID: device.id, battery: device.aggregateBattery)
        case let .disconnected(device):
            // A departed device's battery is never shown: its last reading is no longer live.
            NotchAudioHUD(kind: .deviceDisconnected, deviceName: device.name, volume: nil, isMuted: false,
                          deviceStyle: device.category, deviceID: device.id)
        }
    }
}
