public enum ServiceKind: String, CaseIterable, Codable, Hashable, Sendable {
    case media
    case calendar
    case shelf
    case screenshot
    case clipboard
    case camera
    case audioDevices
    case battery
    case caffeine
    case keyboardLock
    case systemStats
    case downloads
    case meetings
    case focus
    case audioMeter
    case activityEvents
    case browserActivity
}

public enum ProviderMode: String, CaseIterable, Codable, Sendable {
    case real
    case mock
    case denied
    case unavailable
    case failure
}

public enum ServiceFailure: Error, Equatable, Sendable {
    case stageTwoRequired(ServiceKind)
    case unavailable(ServiceKind)
    case permissionDenied(PermissionKind)
    case permissionRequestsDisabled
    case unsupportedOperation(ServiceKind)
}
