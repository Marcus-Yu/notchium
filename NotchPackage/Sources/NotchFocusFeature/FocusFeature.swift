import NotchCore
import NotchServices

public enum FocusFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .focus,
        name: "Focus",
        summary: "Deterministic local timers and nonjudgmental statistics.",
        requiredPermissions: [.notifications, .safariExtension, .chromiumExtension]
    )
}
