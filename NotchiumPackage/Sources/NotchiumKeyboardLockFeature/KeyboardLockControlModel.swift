import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation

@MainActor
@Observable
public final class KeyboardLockControlModel: NotchKeyboardLockControlling {
    public private(set) var isLocked = false
    public private(set) var isBusy = false
    public private(set) var emergencyUnlockStartedAt: Date?
    public private(set) var guidance: NotchKeyboardLockGuidance?

    @ObservationIgnored private static let explanationKey = "keyboardLock.didShowExplanation"
    @ObservationIgnored private let service: any KeyboardLockService
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var operation: Task<Void, Never>?

    public init(
        service: any KeyboardLockService,
        preferences: UserDefaults = .standard
    ) {
        self.service = service
        self.preferences = preferences
    }

    deinit {
        observation?.cancel()
        operation?.cancel()
    }

    public func start() {
        guard observation == nil else { return }
        observation = Task { [weak self, service] in
            for await snapshot in await service.updates() {
                guard !Task.isCancelled, let self else { return }
                self.receive(snapshot)
            }
        }
    }

    public func stop() {
        observation?.cancel(); observation = nil
        operation?.cancel(); operation = nil
        service.shutdown()
        isLocked = false
        isBusy = false
        emergencyUnlockStartedAt = nil
    }

    public func toggleLock() {
        guard !isBusy else { return }
        isBusy = true
        operation?.cancel()
        let wasLocked = isLocked
        operation = Task { [weak self, service] in
            if wasLocked {
                await service.unlock()
            } else {
                do {
                    try await service.lock(policy: .productDefault)
                } catch let failure as KeyboardLockFailure {
                    guard let self else { return }
                    switch failure {
                    case let .permissionsRequired(permissions):
                        self.guidance = .permissionsRequired(permissions)
                    case .eventTapUnavailable:
                        self.guidance = .unavailable
                    case .secureInputEnabled:
                        self.guidance = .secureInputEnabled
                    }
                } catch {
                    self?.guidance = .unavailable
                }
            }
            self?.isBusy = false
        }
    }

    public func dismissGuidance() { guidance = nil }

    public func openSystemSettings() {
        guard case let .permissionsRequired(permissions) = guidance else { return }
        service.openPermissionSettings(for: permissions)
        guidance = nil
    }

    private func receive(_ snapshot: KeyboardLockSnapshot) {
        let becameLocked = snapshot.isLocked && !isLocked
        isLocked = snapshot.isLocked
        emergencyUnlockStartedAt = snapshot.emergencyUnlockStartedAt

        if becameLocked, !preferences.bool(forKey: Self.explanationKey) {
            preferences.set(true, forKey: Self.explanationKey)
            guidance = .firstLock
        }
        switch snapshot.issue {
        case let .permissionsRequired(permissions): guidance = .permissionsRequired(permissions)
        case .eventTapDisabled: guidance = .lockEnded
        case .eventTapUnavailable: guidance = .unavailable
        case .secureInputEnabled: guidance = .secureInputEnabled
        case nil: break
        }
    }
}
