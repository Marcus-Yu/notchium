import NotchiumCore
import NotchiumServices

public enum ShelfFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .shelf,
        name: "File Shelf",
        summary: "Temporary file references, transfer and screenshot activities, and native sharing.",
        requiredPermissions: [.userSelectedFiles, .downloadsFolder]
    )
}
