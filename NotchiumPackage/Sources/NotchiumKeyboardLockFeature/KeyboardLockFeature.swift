import NotchiumCore
import NotchiumServices

public enum KeyboardLockFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .keyboardLock,
        name: "Keyboard Cleaning Lock",
        summary: "Fail-open session event suppression with a fixed escape chord.",
        requiredPermissions: [.accessibility, .inputMonitoring]
    )
}
