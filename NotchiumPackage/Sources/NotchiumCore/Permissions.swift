import Foundation

public enum PermissionKind: String, CaseIterable, Codable, Hashable, Sendable {
    case calendar
    case camera
    case systemAudioRecording
    case accessibility
    case inputMonitoring
    case notifications
    case userSelectedFiles
    case downloadsFolder
    case screenCapture
    case safariExtension
    case chromiumExtension
    case spotifyAccount
    case launchAtLogin
    case keychain
}

public enum PermissionState: String, CaseIterable, Codable, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case revoked
    case unavailable
}
