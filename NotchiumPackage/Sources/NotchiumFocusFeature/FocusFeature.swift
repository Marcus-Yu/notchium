import NotchiumCore
import NotchiumServices

public enum FocusFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .focus,
        name: "Focus Timer",
        summary: "Deadline-based Pomodoro timer with local history, plus macOS Focus awareness.",
        requiredPermissions: [.notifications]
    )
}
