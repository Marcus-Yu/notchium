import NotchiumCore
import NotchiumServices

public enum ShelfFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .shelf,
        name: "File Shelf",
        summary: "App-managed temporary copies and system sharing.",
        requiredPermissions: [.userSelectedFiles, .downloadsFolder]
    )
}
