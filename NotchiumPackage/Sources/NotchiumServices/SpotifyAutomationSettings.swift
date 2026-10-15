import AppKit

@MainActor public enum SpotifyAutomationSettings {
    public static func open() {
        // Open the system application using NSWorkspace; the UI explains the exact pane path.
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
