import Foundation

public enum SystemFeedbackMode: String, Equatable, Sendable {
    case disabled, passive, activeReplacement, unavailable
}

public enum VolumeReplacementFallback: Equatable, Sendable {
    case permissionRequired, unsupportedOutput, tapUnavailable, tapDisabled, operationFailed, suspended
}

public struct VolumeReplacementStatus: Equatable, Sendable {
    public let mode: SystemFeedbackMode
    public let fallback: VolumeReplacementFallback?
    public let canReplaceVolume: Bool
    public let canReplaceMute: Bool

    public init(mode: SystemFeedbackMode, fallback: VolumeReplacementFallback? = nil,
                canReplaceVolume: Bool = false, canReplaceMute: Bool = false) {
        self.mode = mode
        self.fallback = fallback
        self.canReplaceVolume = canReplaceVolume
        self.canReplaceMute = canReplaceMute
    }
}

/// Implemented by the existing device service: this boundary owns no device observation or HUD.
@MainActor
public protocol SystemFeedbackControlling: Sendable {
    func volumeReplacementUpdates() -> AsyncStream<VolumeReplacementStatus>
    func setVolumeReplacementEnabled(_ enabled: Bool, requestPermission: Bool)
    func stopVolumeReplacement()
}
