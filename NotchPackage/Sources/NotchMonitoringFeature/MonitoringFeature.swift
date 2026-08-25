import NotchCore
import NotchServices

public enum MonitoringFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .systemMonitor,
        name: "System Monitor",
        summary: "Documented aggregate system metrics only.",
        requiredPermissions: []
    )
}
