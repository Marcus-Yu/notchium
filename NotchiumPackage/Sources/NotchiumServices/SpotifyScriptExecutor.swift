import AppKit
import Carbon
import Foundation
import Synchronization

public enum SpotifyAutomationPermission: Sendable { case allowed, notDetermined, denied, unavailable }

public struct SpotifyScriptFailure: Error, Equatable, Sendable {
    public let code: Int
    public init(code: Int) { self.code = code }
}

/// Only Sendable values cross the scripting boundary. Tests never send Apple Events.
public protocol SpotifyScriptExecuting: Sendable {
    func permission() async -> SpotifyAutomationPermission
    func execute(_ source: String) async throws -> [String]
}

public struct SystemSpotifyScriptExecutor: SpotifyScriptExecuting {
    // All NSAppleScript instances, descriptors and permission checks remain on this serial
    // queue. Synchronous Apple Events never block MainActor or a cooperative Swift executor.
    private static let queue = DispatchQueue(label: "com.marcusyu.notchium.spotify-script", qos: .utility)
    public init() {}

    public func permission() async -> SpotifyAutomationPermission {
        return await withCheckedContinuation { continuation in
            Self.queue.async {
                // Permission preflight requires an already-running target. Address its PID
                // directly instead of asking LaunchServices to resolve an installed bundle.
                guard let spotify = NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.spotify.client").first else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                let target = NSAppleEventDescriptor(processIdentifier: spotify.processIdentifier)
                let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
                let permission: SpotifyAutomationPermission
                switch status {
                case noErr: permission = .allowed
                case OSStatus(errAEEventNotPermitted): permission = .denied
                case OSStatus(errAEEventWouldRequireUserConsent): permission = .notDetermined
                default: permission = .unavailable
                }
                continuation.resume(returning: permission)
            }
        }
    }

    /// Match the existing local controller's normal-event consent path: macOS's prompting
    /// AEDeterminePermission form can stall before displaying UI. Read only the application
    /// version, discard it, and recheck OS truth. No song data or playback command is used.
    public func requestAutomationPermission() async throws -> SpotifyAutomationPermission {
        switch await permission() {
        case .allowed: return .allowed
        case .denied: return .denied
        case .unavailable: return .unavailable
        case .notDetermined: break
        }
        _ = try await execute("""
        if application id "com.spotify.client" is not running then error number -600
        with timeout of 5 seconds
            tell application id "com.spotify.client" to get version
        end timeout
        return {"ok"}
        """)
        return await permission()
    }

    public func execute(_ source: String) async throws -> [String] {
        try Task.checkCancellation()
        let cancellation = ScriptCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    guard !cancellation.isCancelled.withLock({ $0 }) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    let result: Result<[String], any Error> = autoreleasepool {
                        guard let script = NSAppleScript(source: source) else {
                            return .failure(MediaFailure.invalidResponse)
                        }
                        var error: NSDictionary?
                        let descriptor = script.executeAndReturnError(&error)
                        if let error {
                            return .failure(SpotifyScriptFailure(code: (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1))
                        }
                        guard descriptor.numberOfItems > 0 else { return .failure(MediaFailure.invalidResponse) }
                        let fields = (1...descriptor.numberOfItems).map { index -> String in
                            guard let item = descriptor.atIndex(index) else { return "" }
                            // Numeric descriptors avoid locale-dependent AppleScript number-to-text conversion.
                            switch item.descriptorType {
                            case typeSInt32: return String(item.int32Value)
                            case typeIEEE64BitFloatingPoint: return String(item.doubleValue)
                            case typeBoolean: return item.booleanValue ? "true" : "false"
                            default: return item.stringValue ?? ""
                            }
                        }
                        return .success(fields)
                    }
                    continuation.resume(with: result)
                }
            }
        } onCancel: {
            cancellation.isCancelled.withLock { $0 = true }
        }
    }
}

private final class ScriptCancellation: Sendable {
    let isCancelled = Mutex(false)
}
