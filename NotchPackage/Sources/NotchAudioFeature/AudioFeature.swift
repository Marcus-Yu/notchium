import NotchCore
import NotchServices

public enum AudioFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .audioDevices,
        name: "Audio Devices",
        summary: "Public Core Audio output capabilities and battery summaries.",
        requiredPermissions: []
    )
}
