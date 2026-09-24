import Foundation
import NotchiumCore

@MainActor
public protocol NotchCaffeineControlling: AnyObject {
    var mode: CaffeineMode { get }
    var isBusy: Bool { get }
    func cycleMode()
    func keepDisplayAwake()
}

public enum NotchKeyboardLockGuidance: Equatable, Sendable {
    case permissionsRequired(Set<PermissionKind>)
    case firstLock
    case lockEnded
    case unavailable
    case secureInputEnabled
}

@MainActor
public protocol NotchKeyboardLockControlling: AnyObject {
    var isLocked: Bool { get }
    var isBusy: Bool { get }
    var emergencyUnlockStartedAt: Date? { get }
    var guidance: NotchKeyboardLockGuidance? { get }
    func toggleLock()
    func dismissGuidance()
    func openSystemSettings()
}
