import NotchiumCore
import NotchiumServices

public enum ClipboardFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .clipboard,
        name: "Clipboard History",
        summary: "Fail-closed local clipboard metadata and payload management.",
        requiredPermissions: [.keychain]
    )
}
