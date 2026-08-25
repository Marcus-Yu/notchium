import NotchActivitiesFeature
import NotchAudioFeature
import NotchCaffeineFeature
import NotchCalendarFeature
import NotchCameraFeature
import NotchClipboardFeature
import NotchCore
import NotchFocusFeature
import NotchKeyboardLockFeature
import NotchMediaFeature
import NotchMonitoringFeature
import NotchPagesFeature
import NotchShelfFeature

public enum FeatureCatalog {
    public static let descriptors: [FeatureDescriptor] = [
        FeatureDescriptor(
            id: .shell,
            name: "Notch Shell",
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
