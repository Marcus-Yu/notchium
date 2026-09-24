import NotchiumCore
import NotchiumServices

public enum CaffeineFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .caffeine,
        name: "Caffeine",
        summary: "Session-scoped system or system-and-display power assertions.",
        requiredPermissions: []
    )
}
