import SwiftUI

public extension EnvironmentValues {
    // Optional render overrides are inherited from the shell. Production uses the native
    // preferences; fixtures can exercise the same feature views without changing macOS.
    @Entry var notchReduceMotionOverride: Bool? = nil
    @Entry var notchReduceTransparencyOverride: Bool? = nil
    @Entry var notchIncreaseContrastOverride: Bool? = nil
}

@propertyWrapper
public struct NotchReducedMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var systemValue
    @Environment(\.notchReduceMotionOverride) private var override

    public init() {}
    public var wrappedValue: Bool { override ?? systemValue }
}

@propertyWrapper
public struct NotchReducedTransparency: DynamicProperty {
    @Environment(\.accessibilityReduceTransparency) private var systemValue
    @Environment(\.notchReduceTransparencyOverride) private var override

    public init() {}
    public var wrappedValue: Bool { override ?? systemValue }
}

@propertyWrapper
public struct NotchIncreasedContrast: DynamicProperty {
    @Environment(\.colorSchemeContrast) private var systemValue
    @Environment(\.notchIncreaseContrastOverride) private var override

    public init() {}
    public var wrappedValue: Bool { override ?? (systemValue == .increased) }
}
