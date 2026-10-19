import NotchiumCore

extension SetupPermission {
    var title: String {
        switch self {
        case .calendar: "Calendars"
        case .reminders: "Reminders"
        case .spotify: "Spotify Automation"
        case .camera: "Camera"
        case .systemAudio: "System Audio Recording"
        case .volumeKeys: "Accessibility for Volume Keys"
        case .screenshots: "Screenshot Folder"
        case .clipboard: "Clipboard History"
        case .clipboardAccess: "macOS Pasteboard Access"
        case .files: "Shelf & File Actions"
        case .shortcuts: "Apple Shortcuts"
        case .focus: "System Focus Status"
        case .notifications: "In-App Notifications"
        case .keychain: "Clipboard Encryption"
        case .closedLid: "Caffeine & Closed-Lid Mode"
        }
    }
    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .spotify: "music.note"
        case .camera: "camera"
        case .systemAudio: "waveform"
        case .volumeKeys: "hand.raised"
        case .screenshots: "camera.viewfinder"
        case .clipboard: "doc.on.clipboard"
        case .clipboardAccess: "hand.raised.square"
        case .files: "folder"
        case .shortcuts: "command"
        case .focus: "moon"
        case .notifications: "bell"
        case .keychain: "lock.shield"
        case .closedLid: "cup.and.saucer"
        }
    }
    var summary: String {
        switch self {
        case .calendar: "Upcoming events and meeting links. Event data stays on this Mac; setup reads no events."
        case .reminders: "Quick Reminder saves to your selected list only when you choose Add. Setup creates nothing."
        case .spotify: "Local song information and playback controls. Setup requests consent without reading songs or changing playback."
        case .camera: "Mirror previews only while open. No microphone, photos, or recordings."
        case .systemAudio: "Spotify waveform and per-app volume. In-memory audio, never recorded to disk."
        case .volumeKeys: "Optional replacement of the macOS volume HUD. No typed text is read or stored."
        case .screenshots: "Observe new screenshot files in a folder you select. No screen capture."
        case .clipboard: "An explicit choice about monitoring future copies and saving encrypted local history."
        case .clipboardAccess: "The current macOS privacy state for programmatic Clipboard reads, separate from app consent."
        case .files: "Access only the files and folders you select, with saved bookmarks."
        case .shortcuts: "Run your selected shortcuts. Each shortcut manages its own permissions."
        case .focus: "Read Focus on/off status when this build has the required entitlement."
        case .notifications: "Notchium’s own alerts appear inside the notch."
        case .keychain: "A Keychain-held key protects saved Clipboard history."
        case .closedLid: "Keep-awake support and the distribution’s helper limitations."
        }
    }
}

extension SetupAuthorization {
    var label: String {
        switch self {
        case .notDetermined: "Not Set Up"
        case .granted: "Granted"
        case .denied: "Denied"
        case .restricted: "Restricted by macOS"
        case .needsSystemSettings: "Needs System Settings"
        case .needsFullAccess: "Needs Full Access"
        case .unavailable: "Unavailable"
        case .requiresUserSelection: "Requires User Selection"
        case .selectionSaved: "Folder Selected"
        case .requiresApplication: "Requires Spotify"
        case .notPregrantable: "Cannot Grant in Advance"
        case .noPermissionRequired: "No OS Permission Required"
        }
    }
}
