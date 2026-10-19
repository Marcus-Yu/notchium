import Foundation

public enum SetupPermission: String, CaseIterable, Codable, Identifiable, Sendable {
    case calendar, reminders, spotify, camera, systemAudio, volumeKeys, screenshots
    case clipboard, clipboardAccess, files, shortcuts, focus, notifications, keychain, closedLid
    public var id: String { rawValue }
}

/// OS truth is deliberately absent from the durable onboarding record.
public struct OnboardingState: Codable, Equatable, Sendable {
    public enum Step: String, Codable, Sendable { case welcome, overview, permissions, review, ready }
    public enum Completion: String, Codable, Sendable { case userCompleted, legacyRecognized }
    public var schemaVersion = 1
    public var step: Step = .welcome
    public var currentPermission: SetupPermission = .calendar
    public var reviewed: Set<SetupPermission> = []
    public var clipboardChoice: Bool?
    public var completion: Completion?
    public init() {}
    public var requiresOnboarding: Bool { completion == nil }
}

public enum SetupAuthorization: String, Equatable, Sendable {
    case notDetermined, granted, denied, restricted, needsSystemSettings, needsFullAccess, unavailable
    case requiresUserSelection, selectionSaved, requiresApplication, notPregrantable, noPermissionRequired

    public var acceptsAcknowledgment: Bool {
        switch self {
        case .restricted, .unavailable, .notPregrantable, .noPermissionRequired: true
        default: false
        }
    }
}

public struct SetupPermissionStatus: Equatable, Sendable {
    public let authorization: SetupAuthorization
    public let detail: String
    public init(_ authorization: SetupAuthorization, _ detail: String = "") {
        self.authorization = authorization
        self.detail = detail
    }
}
