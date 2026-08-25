import NotchCore
import NotchServices

public enum ActivitiesFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .activities,
        name: "Dynamic Island Activities",
        summary: "Typed local activity events rendered by the app shell.",
        requiredPermissions: [.notifications]
    )
}
