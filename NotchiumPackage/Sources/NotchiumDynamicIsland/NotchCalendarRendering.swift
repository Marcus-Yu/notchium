import SwiftUI

/// Calendar owns its data and views; the shell only selects a surface.
@MainActor public protocol NotchCalendarRendering: AnyObject {
    var reminderVisible: Bool { get }
    func reminderBanner(action: @escaping @MainActor () -> Void) -> AnyView
    func setReminderHovered(_ hovered: Bool)
    func homeCalendar(openCalendar: @escaping @MainActor () -> Void) -> AnyView
    func expandedCalendar() -> AnyView
}

extension EnvironmentValues {
    @Entry public var notchCalendarPageVisible = true
}

public extension NotchCalendarRendering {
    func homeCalendar(openCalendar: @escaping @MainActor () -> Void) -> AnyView { AnyView(Button("Open Calendar", action: openCalendar).buttonStyle(.plain)) }
}
