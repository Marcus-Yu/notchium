import AppKit
import Carbon
import NotchiumCore

/// Raw OSStatus stays inside the service layer. No AppleScript or playback is used for consent.
public protocol SpotifyAutomationAuthorizing: Sendable {
    func authorization(prompt: Bool) async -> Int32
}

public struct SystemSpotifyAutomationAuthorizer: SpotifyAutomationAuthorizing {
    // Consent may wait indefinitely for a human. It must not queue behind scripting or
    // prevent independent nonprompting status checks. Descriptors never cross this boundary.
    private static let consentQueue = DispatchQueue(label: "com.marcusyu.notchium.spotify-consent")
    private static let checkQueue = DispatchQueue(label: "com.marcusyu.notchium.spotify-preflight")
    public init() {}
    public func authorization(prompt: Bool) async -> Int32 {
        await withCheckedContinuation { continuation in
            (prompt ? Self.consentQueue : Self.checkQueue).async {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
                    .first(where: { !$0.isTerminated && $0.isFinishedLaunching }) else {
                    continuation.resume(returning: Int32(procNotFound))
                    return
                }
                let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
                continuation.resume(returning: AEDeterminePermissionToAutomateTarget(
                    target.aeDesc, typeWildCard, typeWildCard, prompt))
            }
        }
    }
}

/// Owns one native request even after the UI's waiting budget expires. Never cancels
/// an OS authorization sheet, starts duplicate requests, or treats elapsed time as a grant.
@MainActor public final class SpotifySetupAuthorization {
    private let application: any SpotifyApplicationLaunching
    private let authorizer: any SpotifyAutomationAuthorizing
    private let clock: any AppClock
    private var requestOperation: SpotifyAuthorizationOperation?
    private var checkOperation: SpotifyAuthorizationOperation?

    public init(application: any SpotifyApplicationLaunching = SystemSpotifyApplicationLauncher(),
                authorizer: any SpotifyAutomationAuthorizing = SystemSpotifyAutomationAuthorizer(),
                clock: any AppClock = ContinuousAppClock()) {
        self.application = application
        self.authorizer = authorizer
        self.clock = clock
    }

    public func status() async -> SetupPermissionStatus {
        if let requestOperation {
            guard requestOperation.isComplete else { return Self.waiting }
            self.requestOperation = nil
        }
        guard await application.isSpotifyInstalled() else {
            return .init(.unavailable, "Spotify is not installed. Continue without it, then install Spotify and repair access in Settings → Permissions.")
        }
        guard await application.isSpotifyRunning() else {
            return .init(.requiresApplication, "Open Spotify to verify or request Automation. No playback starts during setup.")
        }
        if checkOperation == nil {
            let authorizer = authorizer
            checkOperation = SpotifyAuthorizationOperation { Self.status(for: await authorizer.authorization(prompt: false)) }
        }
        guard let operation = checkOperation else { return Self.waiting }
        let result = await operation.value(clock: clock, waiting: .seconds(3))
        if operation.isComplete { checkOperation = nil }
        return result ?? .init(.needsSystemSettings, "macOS has not returned Spotify’s authorization status. No grant is verified. Refresh later or continue without Spotify.")
    }

    public func request() async throws {
        if let requestOperation, !requestOperation.isComplete { return }
        let application = application, authorizer = authorizer, clock = clock
        let operation = SpotifyAuthorizationOperation {
            guard await application.isSpotifyInstalled() else {
                return .init(.unavailable, "Spotify is not installed. Install it and retry in Settings → Permissions.")
            }
            if !(await application.isSpotifyRunning()) {
                do { try await application.launchSpotify() }
                catch { return .init(.needsSystemSettings, "Spotify could not be opened. Open it yourself, then retry access.") }
            }
            // LaunchServices completion is not proof that Spotify is ready as an AE target.
            for _ in 0..<20 {
                if await application.isSpotifyRunning() { break }
                do { try await clock.sleep(for: .milliseconds(250)) }
                catch { return .init(.needsSystemSettings, "Spotify launch was interrupted. Retry access.") }
            }
            guard await application.isSpotifyRunning() else {
                return .init(.requiresApplication, "Spotify did not become ready. Open it and retry access.")
            }
            NSApp?.activate(ignoringOtherApps: true)
            return Self.status(for: await authorizer.authorization(prompt: true))
        }
        requestOperation = operation
        // Release the wizard, not the OS request. The native sheet can still be answered.
        let result = await operation.value(clock: clock, waiting: .seconds(30))
        if let result, result.authorization != .granted {
            throw SpotifySetupRequestFailure(message: result.detail)
        }
        if result == nil { throw SpotifySetupRequestFailure(message: Self.waiting.detail) }
    }

    static let waiting = SetupPermissionStatus(.needsSystemSettings,
        "macOS is still waiting to resolve Spotify access. If an authorization dialog is open, answer it. You can continue without Spotify while the request remains pending, then refresh in Settings → Permissions. No access has been verified.")

    static func status(for code: Int32) -> SetupPermissionStatus {
        switch code {
        case noErr: .init(.granted)
        case Int32(errAEEventNotPermitted):
            .init(.denied, "macOS denied Spotify Automation (−1743). Enable Notchium → Spotify in System Settings → Privacy & Security → Automation, then refresh. You may need to quit and reopen Notchium.")
        case Int32(errAEEventWouldRequireUserConsent):
            .init(.notDetermined, "macOS has not granted Spotify access (−1744). Request Access to ask for consent, or continue without Spotify.")
        case Int32(procNotFound), Int32(connectionInvalid):
            .init(.requiresApplication, "Spotify stopped or could not be contacted (\(code)). Open Spotify and retry access.")
        case Int32(errAETimeout):
            .init(.needsSystemSettings, "The Spotify authorization operation timed out (−1712). Access is unverified. Refresh or retry when Spotify responds, or continue without Spotify.")
        default:
            .init(.needsSystemSettings, "macOS could not verify Spotify Automation (error \(code)). Open Spotify, refresh or retry access, or continue without Spotify.")
        }
    }
}

public struct SpotifySetupRequestFailure: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

/// A bounded wait around an owned, potentially noncancellable OS operation. A task group
/// would wait for its blocked child on exit. Only one underlying operation is retained.
@MainActor private final class SpotifyAuthorizationOperation {
    private var task: Task<Void, Never>?
    private var result: SetupPermissionStatus?
    private var nextID = 0
    private var waiters: [Int: (CheckedContinuation<SetupPermissionStatus?, Never>, Task<Void, Never>)] = [:]
    var isComplete: Bool { result != nil }

    init(work: @escaping @MainActor () async -> SetupPermissionStatus) {
        task = Task { [weak self] in
            let result = await work()
            self?.complete(result)
        }
    }
    func value(clock: any AppClock, waiting duration: Duration) async -> SetupPermissionStatus? {
        if let result { return result }
        nextID += 1
        let id = nextID
        return await withCheckedContinuation { continuation in
            let timer = Task { [weak self] in
                do { try await clock.sleep(for: duration) } catch { return }
                guard !Task.isCancelled else { return }
                self?.waiters.removeValue(forKey: id)?.0.resume(returning: nil)
            }
            waiters[id] = (continuation, timer)
        }
    }
    private func complete(_ result: SetupPermissionStatus) {
        self.result = result
        task = nil
        let pending = waiters
        waiters.removeAll()
        for (continuation, timer) in pending.values {
            timer.cancel()
            continuation.resume(returning: result)
        }
    }
    isolated deinit {
        task?.cancel()
        for (_, timer) in waiters.values { timer.cancel() }
    }
}
