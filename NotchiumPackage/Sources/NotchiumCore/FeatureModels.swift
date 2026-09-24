import Foundation

public enum FeatureID: String, CaseIterable, Codable, Hashable, Sendable {
    case shell
    case media
    case calendar
    case shelf
    case camera
    case audioDevices
    case caffeine
    case keyboardLock
    case clipboard
    case systemMonitor
    case activities
    case pages
    case focus
    case developerPanel
}

public enum CaffeineMode: String, Codable, CaseIterable, Equatable, Sendable {
    case off
    case system
    case systemAndDisplay

    public var isActive: Bool { self != .off }
}

public enum AvailabilityReason: String, Codable, Hashable, Sendable {
    case available
    case disabledByFeatureFlag
    case permissionNotDetermined
    case permissionDenied
    case permissionRestricted
    case permissionRevoked
    case unsupportedHardware
    case unsupportedDistribution
    case stageTwoRequired
    case temporarilyUnavailable
}

public enum FeatureAvailability: Codable, Equatable, Sendable {
    case available
    case limited(AvailabilityReason)
    case unavailable(AvailabilityReason)

    public var isUsable: Bool {
        switch self {
        case .available, .limited:
            true
        case .unavailable:
            false
        }
    }
}

public struct FeatureCapability: Codable, Equatable, Sendable {
    public let feature: FeatureID
    public let availability: FeatureAvailability

    public init(feature: FeatureID, availability: FeatureAvailability) {
        self.feature = feature
        self.availability = availability
    }
}

public struct FeatureDescriptor: Identifiable, Equatable, Sendable {
    public let id: FeatureID
    public let name: String
    public let summary: String
    public let requiredPermissions: Set<PermissionKind>

    public init(
        id: FeatureID,
        name: String,
        summary: String,
        requiredPermissions: Set<PermissionKind> = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.requiredPermissions = requiredPermissions
    }
}

public protocol FeatureModule: Sendable {
    static var descriptor: FeatureDescriptor { get }
}
