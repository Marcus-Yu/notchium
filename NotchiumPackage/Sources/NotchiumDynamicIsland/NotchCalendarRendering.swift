import SwiftUI

/// Calendar owns its data and views; the shell only selects a surface.
@MainActor public protocol NotchCalendarRendering: AnyObject {
    var reminderVisible: Bool { get }
    func reminderBanner() -> AnyView
    func setReminderHovered(_ hovered: Bool)
    func expandedCalendar() -> AnyView
}

extension EnvironmentValues {
    @Entry public var notchCalendarPageVisible = true
}
