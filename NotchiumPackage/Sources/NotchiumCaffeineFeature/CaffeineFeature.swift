import NotchiumCore
import NotchiumServices

public enum CaffeineFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .caffeine,
        name: "Caffeine",
        summary: "Time-bounded or indefinite public power assertions.",
        requiredPermissions: []
    )
}
