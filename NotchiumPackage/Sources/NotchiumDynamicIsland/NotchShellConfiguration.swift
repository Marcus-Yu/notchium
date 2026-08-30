import SwiftUI

public enum NotchAppearanceOverride: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public enum NotchAccessibilityOverride: String, CaseIterable, Sendable {
    case system
    case on
    case off

    func resolve(systemValue: Bool) -> Bool {
        switch self {
        case .system: systemValue
        case .on: true
        case .off: false
        }
    }
}

public struct NotchShellRenderConfiguration: Equatable, Sendable {
    public var appearance: NotchAppearanceOverride
    public var reduceMotion: NotchAccessibilityOverride
    public var reduceTransparency: NotchAccessibilityOverride
    public var showsGeometryOverlay: Bool

    public init(
        appearance: NotchAppearanceOverride = .system,
        reduceMotion: NotchAccessibilityOverride = .system,
        reduceTransparency: NotchAccessibilityOverride = .system,
        showsGeometryOverlay: Bool = false
    ) {
        self.appearance = appearance
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.showsGeometryOverlay = showsGeometryOverlay
    }

    public static let automatic = NotchShellRenderConfiguration()
}

public struct NotchShellAccessibilityConfiguration: Equatable, Sendable {
    public let reduceMotion: Bool
    public let reduceTransparency: Bool
    public let increaseContrast: Bool

    public init(
        reduceMotion: Bool,
        reduceTransparency: Bool,
        increaseContrast: Bool
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }

    public static func resolve(
        renderConfiguration: NotchShellRenderConfiguration,
        systemReduceMotion: Bool,
        systemReduceTransparency: Bool,
        systemIncreaseContrast: Bool
    ) -> NotchShellAccessibilityConfiguration {
        NotchShellAccessibilityConfiguration(
            reduceMotion: renderConfiguration.reduceMotion.resolve(
                systemValue: systemReduceMotion
            ),
            reduceTransparency: renderConfiguration.reduceTransparency.resolve(
                systemValue: systemReduceTransparency
            ),
            increaseContrast: systemIncreaseContrast
        )
    }
}
