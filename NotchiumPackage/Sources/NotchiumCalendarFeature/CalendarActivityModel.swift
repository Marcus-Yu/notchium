import AppKit
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import SwiftUI

@MainActor
@Observable
public final class CalendarActivityModel: NotchCalendarRendering {
    public private(set) var snapshot = CalendarSnapshot(
        availability: .unavailable(.permissionNotDetermined), permission: .notRequested)
    @ObservationIgnored private let service: any CalendarService
    public let reminders: CalendarReminderCoordinator
    @ObservationIgnored private var observation: Task<Void, Never>?

    public init(service: any CalendarService, coordinator: ActivityCoordinator,
                clock: any AppClock = ContinuousAppClock()) {
        self.service = service
        self.reminders = CalendarReminderCoordinator(activities: coordinator, clock: clock)
    }

    public var reminderVisible: Bool { reminders.current != nil }

    public func start() {
        guard observation == nil else { return }
        observation = Task { [weak self, service] in
            for await snapshot in await service.updates() {
                guard !Task.isCancelled, let self else { return }
                self.snapshot = snapshot
                await self.reminders.update(events: snapshot.upcomingEvents)
            }
        }
        // The first launch asks once. EventKit will not prompt again after a decision.
        Task { [service] in await service.requestAccess() }
    }

    public func stop() {
        observation?.cancel(); observation = nil
        reminders.stop()
        Task { [service] in await service.stop() }
    }

    public func requestAccess() { Task { [service] in await service.requestAccess() } }
    public func setCalendarSelected(_ id: String, selected: Bool) {
        Task { [service] in await service.setCalendarSelected(id, selected: selected) }
    }
    public func refresh() { Task { [service] in try? await service.refresh() } }

    public func dismissReminder() { reminders.dismiss() }
    public func setReminderHovered(_ hovered: Bool) { reminders.setHovered(hovered) }
    public func joinReminder() {
        guard let url = reminders.current?.event.meetingURL else { return }
        NSWorkspace.shared.open(url)
        reminders.dismiss()
    }
    public func reminderBanner(action: @escaping @MainActor () -> Void) -> AnyView {
        AnyView(CalendarReminderView(model: self, openActivity: action))
    }
    public func expandedCalendar() -> AnyView { AnyView(CalendarActivityView(model: self)) }
}
