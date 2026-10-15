import AppKit
import Foundation

public enum SpotifyLifecycleEvent: Sendable { case applicationChanged, sleep, wake }
public protocol SpotifyLifecycleEventProviding: Sendable {
    func events() async -> AsyncStream<SpotifyLifecycleEvent>
}

public struct SpotifyWorkspaceEvents: SpotifyLifecycleEventProviding {
    public init() {}
    @MainActor public func events() async -> AsyncStream<SpotifyLifecycleEvent> {
        let center = NSWorkspace.shared.notificationCenter
        let pair = AsyncStream<SpotifyLifecycleEvent>.makeStream(bufferingPolicy: .bufferingNewest(4))
        let tokens = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                      NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { notification in
                if name == NSWorkspace.willSleepNotification { pair.continuation.yield(.sleep) }
                else if name == NSWorkspace.didWakeNotification { pair.continuation.yield(.wake) }
                else if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                        app.bundleIdentifier == "com.spotify.client" {
                    pair.continuation.yield(.applicationChanged)
                }
            }
        }
        let observation = SpotifyWorkspaceObservation(center: center, tokens: tokens)
        pair.continuation.onTermination = { _ in observation.cancel() }
        return pair.stream
    }
}

// Immutable references; NotificationCenter supports removal from any thread on stream teardown.
private final class SpotifyWorkspaceObservation: @unchecked Sendable {
    let center: NotificationCenter
    let tokens: [any NSObjectProtocol]
    init(center: NotificationCenter, tokens: [any NSObjectProtocol]) { self.center = center; self.tokens = tokens }
    func cancel() { tokens.forEach(center.removeObserver) }
    deinit { cancel() }
}
