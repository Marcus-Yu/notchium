import AppKit

/// Event-driven Spotify lifecycle discovery. This deliberately watches the application
/// workspace rather than polling the process table.
@MainActor
final class SpotifyProcessFinder: NSObject {
    nonisolated static let bundleIdentifier = "com.spotify.client"

    private let workspace: NSWorkspace
    private var onChange: (@MainActor (pid_t?) -> Void)?
    private(set) var processIdentifier: pid_t?

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    @discardableResult
    func start(onChange: @escaping @MainActor (pid_t?) -> Void) -> pid_t? {
        guard self.onChange == nil else { return processIdentifier }
        self.onChange = onChange
        let center = workspace.notificationCenter
        center.addObserver(self, selector: #selector(applicationDidLaunch(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationDidTerminate(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        processIdentifier = runningSpotify()?.processIdentifier
        if let processIdentifier {
            NSLog("[AudioTap] Spotify process found: PID %d", processIdentifier)
        } else {
            NSLog("[AudioTap] Spotify is not running; waiting for launch")
        }
        return processIdentifier
    }

    func stop() {
        workspace.notificationCenter.removeObserver(self)
        onChange = nil
        processIdentifier = nil
    }

    private func runningSpotify() -> NSRunningApplication? {
        workspace.runningApplications.first { $0.bundleIdentifier == Self.bundleIdentifier }
    }

    @objc private func applicationDidLaunch(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.bundleIdentifier == Self.bundleIdentifier else { return }
        update(to: application.processIdentifier)
    }

    @objc private func applicationDidTerminate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.bundleIdentifier == Self.bundleIdentifier,
              application.processIdentifier == processIdentifier else { return }
        update(to: nil)
    }

    private func update(to processIdentifier: pid_t?) {
        guard processIdentifier != self.processIdentifier else { return }
        self.processIdentifier = processIdentifier
        if let processIdentifier {
            NSLog("[AudioTap] Spotify process found: PID %d", processIdentifier)
        } else {
            NSLog("[AudioTap] Spotify terminated; invalidating tap")
        }
        onChange?(processIdentifier)
    }
}
