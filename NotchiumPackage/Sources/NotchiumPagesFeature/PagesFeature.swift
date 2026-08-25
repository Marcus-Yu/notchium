import NotchiumCore

public enum PagesFeature: FeatureModule {
    public static let descriptor = FeatureDescriptor(
        id: .pages,
        name: "Customizable Pages",
        summary: "Deterministically ordered, capability-gated local pages."
    )
}
