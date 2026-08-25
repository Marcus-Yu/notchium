import NotchiumActivitiesFeature
import NotchiumAudioFeature
import NotchiumCaffeineFeature
import NotchiumCalendarFeature
import NotchiumCameraFeature
import NotchiumClipboardFeature
import NotchiumCore
import NotchiumFocusFeature
import NotchiumKeyboardLockFeature
import NotchiumMediaFeature
import NotchiumMonitoringFeature
import NotchiumPagesFeature
import NotchiumShelfFeature

public enum FeatureCatalog {
    public static let descriptors: [FeatureDescriptor] = [
        FeatureDescriptor(
            id: .shell,
            name: "Notchium Shell",
            summary: "Built-in-notch panel with a menu-bar fallback."
        ),
        MediaFeature.descriptor,
        CalendarFeature.descriptor,
        ShelfFeature.descriptor,
        CameraFeature.descriptor,
        AudioFeature.descriptor,
        CaffeineFeature.descriptor,
        KeyboardLockFeature.descriptor,
        ClipboardFeature.descriptor,
        MonitoringFeature.descriptor,
        ActivitiesFeature.descriptor,
        PagesFeature.descriptor,
        FocusFeature.descriptor,
    ]
}
