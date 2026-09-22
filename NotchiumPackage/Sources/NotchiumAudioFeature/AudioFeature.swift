import NotchiumCore
import NotchiumServices

public enum AudioFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .audioDevices,
        name: "Audio",
        summary: "System outputs, volume, and local audio activity.",
        requiredPermissions: []
    )
}
