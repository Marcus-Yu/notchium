import NotchiumCore
import NotchiumServices

public enum CameraFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .camera,
        name: "Camera Mirror",
        summary: "Permission-aware local camera preview.",
        requiredPermissions: [.camera]
    )
}
