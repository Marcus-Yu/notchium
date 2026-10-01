import NotchiumCore
import NotchiumServices

public enum CameraFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .camera,
        name: "Camera Mirror",
        summary: "A small live preview in the notch for checking yourself before a call. Nothing is recorded.",
        requiredPermissions: [.camera]
    )
}
