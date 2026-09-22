import NotchiumCore
import NotchiumServices

public enum CalendarFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .calendar,
        name: "Calendar",
        summary: "Upcoming events and safe meeting-link handoff.",
        requiredPermissions: [.calendar]
    )
}
