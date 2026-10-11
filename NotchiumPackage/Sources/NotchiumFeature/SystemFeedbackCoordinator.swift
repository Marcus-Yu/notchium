import Foundation
import NotchiumServices
import Observation

/// Preferences and lifecycle only. AudioDevicesService owns hardware truth and its single tap;
/// AudioFeatureModel and ActivityCoordinator continue owning feedback and presentation.
@MainActor
@Observable
public final class SystemFeedbackCoordinator {
    public private(set) var replaceVolumeHUD: Bool
    public private(set) var volume = VolumeReplacementStatus(mode: .unavailable)
    public let brightness: SystemFeedbackMode = .unavailable
    public let airPods: SystemFeedbackMode = .passive
    @ObservationIgnored private let control: (any SystemFeedbackControlling)?
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    private static let preferenceKey = "systemFeedback.replaceVolumeHUD"

    public init(control: (any SystemFeedbackControlling)?, preferences: UserDefaults = .standard) {
        self.control = control
        self.preferences = preferences
        replaceVolumeHUD = preferences.bool(forKey: Self.preferenceKey)
    }

    isolated deinit {
        statusTask?.cancel()
        control?.stopVolumeReplacement()
    }

    public func start() {
        guard statusTask == nil, let control else { return }
        let updates = control.volumeReplacementUpdates()
        control.setVolumeReplacementEnabled(replaceVolumeHUD, requestPermission: false)
        statusTask = Task { [weak self] in
            for await status in updates {
                guard let self, !Task.isCancelled else { break }
                self.volume = status
#if DEBUG
                if CommandLine.arguments.contains("--notchium-system-feedback-fixture") {
                    NSLog("SystemFeedback fixture: %@, fallback: %@", status.mode.rawValue, String(describing: status.fallback))
                }
#endif
            }
        }
    }

    public func stop() {
        control?.stopVolumeReplacement()
        statusTask?.cancel()
        statusTask = nil
        volume = VolumeReplacementStatus(mode: control == nil ? .unavailable : .disabled)
    }

    /// Call only from Settings after contextual permission education.
    public func setReplaceVolumeHUD(_ enabled: Bool, requestPermission: Bool = false) {
        replaceVolumeHUD = enabled
        preferences.set(enabled, forKey: Self.preferenceKey)
        control?.setVolumeReplacementEnabled(enabled, requestPermission: enabled && requestPermission)
    }

    public func retryVolumeReplacement() {
        control?.setVolumeReplacementEnabled(replaceVolumeHUD, requestPermission: true)
    }
}
