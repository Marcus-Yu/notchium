import NotchiumCore
import NotchiumServices

public enum ClipboardFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .clipboard,
        name: "Clipboard History",
        summary: "Lean, local clipboard history: recent text, links, images and files.",
        requiredPermissions: []
    )
}
