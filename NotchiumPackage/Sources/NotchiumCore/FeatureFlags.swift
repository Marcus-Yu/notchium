public enum FeatureFlag: String, CaseIterable, Hashable, Sendable {
    case notchShell
    case media
    case calendar
    case shelf
    case camera
    case audioDevices
    case caffeine
    case clipboard
    case systemMonitor
    case activities
    case pages
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

    public static let stageOne = FeatureFlags(values: [
        .notchShell: true,
        .media: false,
        .calendar: false,
        .shelf: false,
        .camera: false,
        .audioDevices: false,
        .caffeine: false,
        .clipboard: false,
        .systemMonitor: false,
        .activities: false,
        .pages: false,
        .focus: false,
    ])

    public static let stageFourMedia = FeatureFlags(values: [.notchShell: true, .media: true])
    public static let stageFiveCalendar = FeatureFlags(values: [
        .notchShell: true, .media: true, .calendar: true
    ])

    public static let stageSixAudio = FeatureFlags(values: [
        .notchShell: true, .media: true, .calendar: true, .audioDevices: true
    ])

    /// Adds the file Shelf, transfer activities and screenshot activities (Stages 14–15).
    public static let stageFifteenFiles = FeatureFlags(values: [
        .notchShell: true,
        .media: true,
        .calendar: true,
        .audioDevices: true,
        .caffeine: true,
        .activities: true,
        .shelf: true,
    ])

    public static let stageSevenActivities = FeatureFlags(values: [
        .notchShell: true,
        .media: true,
        .calendar: true,
        .audioDevices: true,
        .caffeine: true,
        .activities: true,
    ])
}
