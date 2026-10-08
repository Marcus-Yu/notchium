public enum FeatureFlag: String, CaseIterable, Hashable, Sendable {
    case media
    case calendar
    case shelf
    case camera
    case audioDevices
    case caffeine
    case clipboard
    case activities
    case focus
}

public struct FeatureFlags: Equatable, Sendable {
    private let values: [FeatureFlag: Bool]

    public init(values: [FeatureFlag: Bool]) {
        self.values = values
    }

    public subscript(_ flag: FeatureFlag) -> Bool {
        values[flag, default: false]
    }

    /// Adds the file Shelf, transfer activities and screenshot activities (Stages 14–15).
    public static let stageFifteenFiles = FeatureFlags(values: [
        .media: true,
        .calendar: true,
        .audioDevices: true,
        .caffeine: true,
        .activities: true,
        .shelf: true,
    ])

    /// Adds Clipboard history, the Camera mirror, macOS Focus awareness and the Focus Timer (Stages 16–19).
    public static let stageNineteenUtilities = FeatureFlags(values: [
        .media: true,
        .calendar: true,
        .audioDevices: true,
        .caffeine: true,
        .activities: true,
        .shelf: true,
        .clipboard: true,
        .camera: true,
        .focus: true,
    ])
}
