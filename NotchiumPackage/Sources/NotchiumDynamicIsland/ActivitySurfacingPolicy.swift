/// A small environmental filter, applied before the existing priority policy. It decides
/// visibility only: quiet activities keep their identity, data and deadlines.
public enum ActivitySurfacingPolicy {
    /// How much an activity is worth an interruption when the user is watching or presenting.
    enum Importance: Equatable {
        /// Critical, urgent or answering the user's own action.
        case essential
        /// Ongoing state and early heads-ups: quiet only while presenting.
        case ambient
        /// System chatter: quiet over fullscreen media and while presenting.
        case routine
    }

    public static func shouldSurface(_ activity: NotchActivity,
                                     notificationKind: NotchNotification.Kind? = nil,
                                     in context: NotchPresentationContext) -> Bool {
        switch context {
        case .sleeping: false
        case .normal, .fullscreenApp: true
        case .immersiveMedia: importance(of: activity, notificationKind: notificationKind) != .routine
        case .presentationLike: importance(of: activity, notificationKind: notificationKind) == .essential
        }
    }

    static func importance(of activity: NotchActivity, notificationKind: NotchNotification.Kind?) -> Importance {
        if activity.priority == .critical { return .essential }
        if let notificationKind {
            switch notificationKind {
            case .criticalBattery, .reminder5, .transferFinished, .transferFailed, .focusTimerComplete,
                 .volume, .mute, .actionSucceeded, .actionFailed, .reminderAdded, .shelfAdded:
                return .essential
            case .lowBattery, .reminder30, .reminder60, .transferActive, .focusTimer, .focusTimerBesideMusic:
                return .ambient
            case .outputDeviceChanged, .charging, .powerDisconnected, .screenshot, .focusModeChanged:
                return .routine
            }
        }
        switch activity.kind {
        // Volume and brightness answer a key the user just pressed.
        case .systemHUD: return .essential
        case .audioDevice, .charging, .screenshot, .focus: return .routine
        case .media, .battery, .calendar, .meeting, .download, .clipboard, .notification, .pomodoro: return .ambient
        }
    }
}
