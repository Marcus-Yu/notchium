import Foundation

enum VolumeHardwareKey: Int, Sendable {
    case up = 0, down = 1, mute = 7
}

struct VolumeHardwareState: Equatable, Sendable {
    let deviceID: UInt32
    let volumeElements: [UInt32]
    let volumes: [Double]
    let muteElements: [UInt32]
    let muted: Bool?
    var volume: Double? { volumes.max() }
    var supportsVolume: Bool { !volumes.isEmpty && volumeElements.count == volumes.count }
    var supportsMute: Bool { !muteElements.isEmpty && muted != nil }
}

protocol VolumeKeyHardware {
    func defaultOutputID() -> UInt32
    func read(_ deviceID: UInt32) -> VolumeHardwareState?
    func writeVolume(_ values: [Double], state: VolumeHardwareState) -> Bool
    func writeMute(_ muted: Bool, state: VolumeHardwareState) -> Bool
}

enum VolumeKeyResult: Equatable {
    case applied(VolumeHardwareState)
    /// No write was submitted. The owned input can safely be replayed once.
    case notApplied
    /// A HAL write was submitted, so replay could duplicate an actual hardware change.
    case uncertain
}

/// Serial-worker state only. A logical target allows fine steps to accumulate on quantized HAL
/// controls, but only real readback is ever published. External changes invalidate the target.
struct VolumeKeyOperation {
    private var target: (deviceID: UInt32, requested: Double, readback: Double)?

    mutating func apply(_ key: VolumeHardwareKey, fine: Bool, repeated: Bool,
                        deviceID: UInt32, hardware: some VolumeKeyHardware) -> VolumeKeyResult {
        guard hardware.defaultOutputID() == deviceID, let before = hardware.read(deviceID) else {
            target = nil
            return .notApplied
        }
        if key == .mute {
            guard before.supportsMute, let muted = before.muted else { return .notApplied }
            if repeated { return .applied(before) }
            guard hardware.defaultOutputID() == deviceID else { return .notApplied }
            target = nil
            guard hardware.writeMute(!muted, state: before), let after = hardware.read(deviceID),
                  hardware.defaultOutputID() == deviceID, after.muted == !muted else { return .uncertain }
            return .applied(after)
        }
        guard before.supportsVolume, let volume = before.volume else { return .notApplied }
        guard before.muted != true || before.supportsMute else { return .notApplied }
        let base = target.flatMap { $0.deviceID == deviceID && abs($0.readback - volume) < 0.00001
            ? $0.requested : nil } ?? volume
        let step = fine ? 1.0 / 64 : 1.0 / 16
        let requested = min(max(base + (key == .up ? step : -step), 0), 1)
        // Preserve channel balance for outputs without a writable master control.
        let values = before.volumes.map { volume > 0 ? min($0 * requested / volume, 1) : requested }
        guard hardware.defaultOutputID() == deviceID else { return .notApplied }
        if before.muted == true, !hardware.writeMute(false, state: before) { return .uncertain }
        if values != before.volumes, !hardware.writeVolume(values, state: before) { return .uncertain }
        guard let after = hardware.read(deviceID), hardware.defaultOutputID() == deviceID,
              let confirmed = after.volume, after.muted != true else { target = nil; return .uncertain }
        target = (deviceID, requested, confirmed)
        return .applied(after)
    }
}
