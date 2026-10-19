import AppKit
// The imported AX prompt key is a process-constant CFString exposed as a C global.
// All accesses here stay on MainActor, matching the existing audio-device adapter.
@preconcurrency import ApplicationServices
import AVFoundation
import EventKit
import Intents
import NotchiumCore

@MainActor public protocol OnboardingPermissionProviding {
    func status(for permission: SetupPermission) async -> SetupPermissionStatus
    func request(_ permission: SetupPermission) async throws
    func openSettings(for permission: SetupPermission)
    func setClipboardConsent(_ enabled: Bool)
}

/// Permission-only adapter: never fetches events/reminders, opens a camera session,
/// creates an audio tap, reads the pasteboard, or authenticates a Keychain item.
@MainActor public final class NativeOnboardingPermissions: OnboardingPermissionProviding {
    private let store = EKEventStore()
    private let spotify = SystemSpotifyScriptExecutor()
    private let spotifyApp = SystemSpotifyApplicationLauncher()
    private let camera: any CameraService
    private let screenshotFolder: ScreenshotFolderAccess
    private let profile: DistributionProfile
    private let pasteboardBehavior: @MainActor () -> NSPasteboard.AccessBehavior

    public init(camera: any CameraService, profile: DistributionProfile,
                screenshotFolder: ScreenshotFolderAccess = ScreenshotFolderAccess(),
                pasteboardBehavior: @escaping @MainActor () -> NSPasteboard.AccessBehavior = { NSPasteboard.general.accessBehavior }) {
        self.camera = camera
        self.profile = profile
        self.screenshotFolder = screenshotFolder
        self.pasteboardBehavior = pasteboardBehavior
    }

    public func status(for permission: SetupPermission) async -> SetupPermissionStatus {
        switch permission {
        case .calendar: return Self.eventStatus(.event)
        case .reminders: return Self.eventStatus(.reminder)
        case .spotify:
            guard profile != .appStoreSandboxed else {
                return .init(.unavailable, "Local Spotify Automation is unavailable in this distribution.")
            }
            guard spotifyApp.isSpotifyInstalled() else {
                return .init(.unavailable, "Spotify is not installed. Install it later, then repair access in Settings → Permissions.")
            }
            guard spotifyApp.isSpotifyRunning() else {
                return .init(.requiresApplication, "Spotify must be running to verify or request Automation. The next action opens Spotify without playing music.")
            }
            switch await spotify.permission() {
            case .allowed: return .init(.granted)
            case .notDetermined: return .init(.notDetermined)
            case .denied: return .init(.denied, "Allow Notchium to control Spotify in Privacy & Security → Automation.")
            case .unavailable: return .init(.needsSystemSettings, "Spotify could not be contacted. Reopen Spotify and refresh; authorization is unknown.")
            }
        case .camera:
            let authorization = camera.authorization
            let hasCamera = !camera.devices().isEmpty
            if authorization == .authorized {
                return .init(.granted, hasCamera ? "" : "Camera access is granted; no camera is currently attached.")
            }
            // A denied/restricted discovery result is not independent proof that hardware
            // is absent. Keep OS denial authoritative instead of allowing an exception.
            if authorization == .denied { return .init(.denied, "Allow Camera access in Privacy & Security → Camera. Hardware availability is separate from this OS decision.") }
            if authorization == .restricted { return .init(.restricted, "Camera access is restricted by macOS or device management.") }
            guard hasCamera else {
                return .init(.unavailable, "No camera is reported. macOS Camera authorization is not determined; no grant is claimed. Connect a camera and review access in Settings → Permissions.")
            }
            return .init(.notDetermined)
        case .systemAudio:
            return .init(.notPregrantable, "The waveform and per-app mixer use Core Audio process taps. macOS asks when an audio capture starts; this API has no separate permission check or upfront request. Setup does not start capture. Audio stays in memory and is never saved. Review Privacy & Security → Screen & System Audio Recording; macOS may require quitting and reopening the app. Screen Recording is not requested.")
        case .volumeKeys:
            guard profile != .appStoreSandboxed else { return .init(.unavailable, "Volume-key replacement is unavailable in the sandboxed distribution.") }
            if AXIsProcessTrusted() && CGPreflightPostEventAccess() { return .init(.granted) }
            return .init(.needsSystemSettings, "Volume-HUD replacement needs Accessibility trust and event-post access. Enable Notchium in Privacy & Security → Accessibility. Granting access leaves replacement off until you enable it in Audio settings.")
        case .screenshots:
            guard screenshotFolder.resolve() != nil else {
                return .init(.requiresUserSelection, "Choose the folder where macOS saves screenshots. Only new screenshot files in that folder are observed. This is a folder selection, not Screen Recording or universal file access.")
            }
            return .init(.selectionSaved, "A screenshot-folder bookmark is saved. This covers only the selected folder; macOS can revoke file access. If it becomes unavailable, choose it again and reopen Notchium to restart observation with the new selection.")
        case .clipboard:
            return .init(.noPermissionRequired, "This is an app-level consent choice, separate from macOS pasteboard access. Saved text, links, file references and images stay local, encrypted with a Keychain-held key. Retention and pins are managed in Clipboard settings. Setup never reads your Clipboard.")
        case .clipboardAccess:
            let explanation = "Setup reads only this status, not Clipboard contents. macOS has no separate upfront request API."
            switch pasteboardBehavior() {
            case .alwaysAllow: return .init(.granted, "macOS allows programmatic pasteboard access. Monitoring still needs your separate opt-in. " + explanation)
            case .alwaysDeny: return .init(.denied, "macOS denies programmatic pasteboard access. Review Notchium’s pasteboard access in Privacy & Security before enabling monitoring. " + explanation)
            case .default: return .init(.notPregrantable, "macOS has not asked yet. Notchium appears in pasteboard privacy settings after its first access alert. " + explanation)
            case .ask: return .init(.notPregrantable, "macOS will ask when a programmatic read needs access. Ask is not a grant. " + explanation)
            @unknown default: return .init(.needsSystemSettings, "macOS returned an unknown pasteboard access behavior. Refresh or review Privacy & Security; no grant is claimed.")
            }
        case .files:
            return .init(.notPregrantable, "Shelf and Quick Actions use native file pickers and bookmarks for the items you select. Future selections remain under your control. No universal file grant, Full Disk Access, or access to Downloads is requested by setup. Import keeps original files in place.")
        case .shortcuts:
            return .init(.notPregrantable, "Quick Actions runs only shortcuts you select using Apple’s Shortcuts tool. Each shortcut owns its own permissions and may ask when run. Setup does not run a shortcut or grant access on its behalf.")
        case .focus:
            guard profile != .freeDirect, RealFocusService.hasEntitlement() else {
                return .init(.unavailable, "System Focus status requires Apple’s Communication Notifications entitlement, unavailable in this build. The Focus Timer works without it.")
            }
            switch INFocusStatusCenter.default.authorizationStatus {
            case .authorized: return .init(.granted)
            case .notDetermined: return .init(.notDetermined)
            case .denied: return .init(.denied, "Allow sharing Focus status with Notchium in System Settings.")
            case .restricted: return .init(.restricted, "Focus status is restricted by macOS.")
            @unknown default: return .init(.needsSystemSettings, "macOS returned an unknown Focus authorization state.")
            }
        case .notifications:
            return .init(.noPermissionRequired, "Notchium displays its own in-app notifications. It does not post UserNotifications or read other apps’ Notification Center content. No notification authorization is required.")
        case .keychain:
            return .init(.notPregrantable, "Clipboard encryption uses your existing Keychain key. macOS may request access to that specific item after an app update. There is no general Keychain grant. A lookup failure never authorizes replacing a key when encrypted history exists. Setup does not read, replace, or delete keys.")
        case .closedLid:
            return .init(profile == .developerID ? .notPregrantable : .unavailable,
                         profile == .developerID
                         ? "Ordinary Caffeine needs no permission. Experimental closed-lid mode requires a separately installed, signed helper and administrator approval in Caffeine settings. Setup does not install or approve helpers."
                         : "Ordinary Caffeine needs no permission. Closed-lid mode and its privileged helper are excluded from this distribution.")
        }
    }

    public func request(_ permission: SetupPermission) async throws {
        let current = await status(for: permission)
        switch permission {
        case .calendar where current.authorization == .notDetermined || current.authorization == .needsFullAccess:
            _ = try await store.requestFullAccessToEvents()
        case .reminders where current.authorization == .notDetermined || current.authorization == .needsFullAccess:
            _ = try await store.requestFullAccessToReminders()
        case .camera where current.authorization == .notDetermined:
            _ = await camera.requestAccess()
        case .spotify where current.authorization == .notDetermined || current.authorization == .requiresApplication:
            if current.authorization == .requiresApplication { try await spotifyApp.launchSpotify() }
            try Task.checkCancellation()
            NSApp.activate(ignoringOtherApps: true)
            _ = try await spotify.requestAutomationPermission()
        case .volumeKeys where current.authorization == .needsSystemSettings:
            if !AXIsProcessTrusted() {
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            } else if !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
        case .screenshots:
            _ = try await screenshotFolder.choose()
        case .focus where current.authorization == .notDetermined:
            _ = await INFocusStatusCenter.default.requestAuthorization()
        default: break
        }
    }

    public func openSettings(for permission: SetupPermission) {
        // Open the stable root pane; show the exact sub-pane in the row instructions.
        // Deep privacy anchors vary between macOS versions.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    public func setClipboardConsent(_ enabled: Bool) {
        // Store explicit consent without starting the pasteboard observer.
        UserDefaults.standard.set(enabled, forKey: "notchium.clipboard.capture-enabled.v1")
    }

    private static func eventStatus(_ type: EKEntityType) -> SetupPermissionStatus {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .init(.granted)
        case .notDetermined: .init(.notDetermined)
        case .restricted: .init(.restricted, "Access is restricted by macOS or device management. Contact your administrator; setup cannot change this restriction.")
        case .writeOnly: .init(.needsFullAccess, "Write-only access cannot display your calendars. Request full access to use this integration.")
        case .denied: .init(.denied, "Allow full access in Privacy & Security → \(type == .event ? "Calendars" : "Reminders"). macOS does not repeat a denied prompt.")
        @unknown default: .init(.needsSystemSettings, "Unknown authorization state. Review access in System Settings.")
        }
    }
}
