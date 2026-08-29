public enum FeatureFlag: String, CaseIterable, Hashable, Sendable {
    case notchShell
    case media
    case calendar
    case shelf
    case camera
    case audioDevices
    case caffeine
    case keyboardLock
    case clipboard
    case systemMonitor
    case activities
    case pages
    case focus
    case spotifyAudioWaveform
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
        .keyboardLock: false,
        .clipboard: false,
        .systemMonitor: false,
        .activities: false,
        .pages: false,
        .focus: false,
        .spotifyAudioWaveform: false,
    ])

    public static let stageTwoShell = stageOne
}
