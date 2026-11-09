import AppKit
import Foundation

enum TeleprompterSpeechLifecycleEvent: Equatable, Sendable {
    case suspend
    case becameActive
}

/// AppKit's notification centers are obtained only on the main actor. This owner is
/// created for an explicit speech session and removes every subscription on stop.
@MainActor
final class TeleprompterSpeechLifecycleObserver {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(handler: @escaping @Sendable (TeleprompterSpeechLifecycleEvent) -> Void) {
        let workspace = NSWorkspace.shared.notificationCenter
        let registrations = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification),
            (NotificationCenter.default, NSApplication.didBecomeActiveNotification),
        ]
        for (center, name) in registrations {
            guard let event = Self.event(for: name) else { continue }
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in
                handler(event)
            }))
        }
    }

    isolated deinit { stop() }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    static func event(for name: Notification.Name) -> TeleprompterSpeechLifecycleEvent? {
        switch name {
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
             NSWorkspace.sessionDidResignActiveNotification: .suspend
        case NSApplication.didBecomeActiveNotification: .becameActive
        default: nil
        }
    }
}
