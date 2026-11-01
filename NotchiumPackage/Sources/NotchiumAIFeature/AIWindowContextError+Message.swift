import NotchiumCore

extension AIWindowContextError {
    var contextMessage: String {
        switch self {
        case .sharingConsentRequired: "Enable Window Context before capturing a window."
        case .excludedApplication: "This app is excluded from window context."
        case .screenPermissionRequired: "Screen Recording access is required. Review Privacy Settings and reopen Notchium if macOS requests it."
        case .accessibilityPermissionRequired: "Accessibility access is required to verify windows and exclude secure fields."
        case .noWindow: "No eligible active window was found."
        case .windowChanged: "The original window, conversation, or editor changed. Capture the intended window again."
        case .windowValidationFailed: "The original window could not be verified. Capture the intended window again."
        case .secureField: "A secure field is active. This window was not captured."
        case .unavailable: "Window access could not be verified. No successful capture or paste is claimed."
        case .busy: "The previous operation is still finishing."
        case .unsupportedEditor: "This editor is not qualified. Keep the draft and use Copy."
        case .existingText: "The composer has existing text. It was preserved."
        case .clipboardUnavailable: "The clipboard could not be preserved safely. No paste was attempted."
        case .clipboardChanged: "The clipboard changed. Your newer content was preserved."
        case .cancelled: "The local test was stopped."
        }
    }
}
