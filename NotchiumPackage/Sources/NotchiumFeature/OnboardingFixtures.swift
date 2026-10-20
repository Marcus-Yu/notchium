#if DEBUG
import Foundation
import NotchiumCore
import NotchiumPersistence
import NotchiumServices

extension NotchiumApplicationController {
    /// Explicit UI-test-only identity. All permissions and services are synthetic.
    static func onboardingFixture() -> NotchiumApplicationController? {
        let arguments = CommandLine.arguments
        guard arguments.contains("--ui-testing"),
              let index = arguments.firstIndex(of: "--notchium-onboarding-fixture"),
              index + 1 < arguments.count, let id = UUID(uuidString: arguments[index + 1]) else { return nil }
        let preferences = UserDefaults(suiteName: "Notchium.SetupUITests.\(id.uuidString)")!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Notchium.SetupUITests.\(id.uuidString)")
        let permissions = FixtureSetupPermissions(denied: arguments.contains("--notchium-setup-denied"),
            spotifyDenied: arguments.contains("--notchium-setup-spotify-denied"))
        let model = OnboardingModel(store: OnboardingStore(preferences: preferences, supportDirectory: directory),
                                    permissions: permissions)
        let controller = NotchiumApplicationController(environment: .mock(clock: ContinuousAppClock()),
            actionStore: QuickActionStore(preferences: preferences), onboarding: model)
        return controller
    }
}

@MainActor private final class FixtureSetupPermissions: OnboardingPermissionProviding {
    private var states: [SetupPermission: SetupPermissionStatus] = [:]
    private let denied: Bool
    private let spotifyDenied: Bool
    init(denied: Bool, spotifyDenied: Bool) {
        self.denied = denied
        self.spotifyDenied = spotifyDenied
        for permission in SetupPermission.allCases {
            switch permission {
            case .systemAudio, .clipboardAccess, .files, .shortcuts, .keychain:
                states[permission] = .init(.notPregrantable, "This requirement cannot be granted universally in advance. Review its feature-specific system flow.")
            case .focus, .closedLid:
                states[permission] = .init(.unavailable, "This capability is unavailable in this test distribution.")
            case .clipboard, .notifications: states[permission] = .init(.noPermissionRequired)
            case .screenshots: states[permission] = .init(.requiresUserSelection)
            default: states[permission] = .init(.notDetermined)
            }
        }
    }
    func status(for permission: SetupPermission) async -> SetupPermissionStatus { states[permission]! }
    func request(_ permission: SetupPermission) async throws {
        states[permission] = .init((denied || (permission == .spotify && spotifyDenied)) ? .denied : (permission == .screenshots ? .selectionSaved : .granted),
                                   denied ? "Access was denied. Review it in System Settings, then refresh." : "")
    }
    func openSettings(for permission: SetupPermission) { }
    func setClipboardConsent(_ enabled: Bool) { }
}
#endif
