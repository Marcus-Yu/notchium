import NotchiumCore

public protocol PermissionAuthorizing: Sendable {
    func state(for permission: PermissionKind) async -> PermissionState
    func request(_ permission: PermissionKind) async throws -> PermissionState
}

public struct RealPermissionAuthorizer: PermissionAuthorizing {
    public init() {}

    public func state(for permission: PermissionKind) async -> PermissionState {
        .notDetermined
    }

    public func request(_ permission: PermissionKind) async throws -> PermissionState {
        // Stage 1 never initiates a system prompt.
        throw ServiceFailure.permissionRequestsDisabled
    }
}

public actor MockPermissionAuthorizer: PermissionAuthorizing {
    private var states: [PermissionKind: PermissionState]

    public init(states: [PermissionKind: PermissionState] = [:]) {
        self.states = states
    }

    public func state(for permission: PermissionKind) -> PermissionState {
        states[permission, default: .notDetermined]
    }

    public func request(_ permission: PermissionKind) -> PermissionState {
        states[permission, default: .notDetermined]
    }

    public func setState(_ state: PermissionState, for permission: PermissionKind) {
        states[permission] = state
    }
}
