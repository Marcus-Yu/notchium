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
    public private(set) var selectedEventID: UUID?
    @ObservationIgnored private let service: any CalendarService
    @ObservationIgnored private let openMeeting: @MainActor (URL) -> Void
    public let reminders: CalendarReminderCoordinator
    @ObservationIgnored private var observation: Task<Void, Never>?

    public init(service: any CalendarService, coordinator: ActivityCoordinator,
                clock: any AppClock = ContinuousAppClock(),
                openMeeting: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.service = service
        self.openMeeting = openMeeting
        self.reminders = CalendarReminderCoordinator(activities: coordinator, clock: clock)
    }

    public var reminderVisible: Bool { reminders.current != nil }

    public var secondaryEvents: [CalendarEventSummary] { Array(snapshot.upcomingEvents.dropFirst()) }

    public func toggleEvent(_ id: UUID) {
        guard secondaryEvents.contains(where: { $0.id == id }) else { return }
        selectedEventID = selectedEventID == id ? nil : id
    }

    func receive(_ snapshot: CalendarSnapshot) {
        self.snapshot = snapshot
        if let selectedEventID,
           !snapshot.upcomingEvents.contains(where: { $0.id == selectedEventID }) {
            self.selectedEventID = nil
        }
    }

    public func joinEvent(_ id: UUID) {
        guard let url = snapshot.upcomingEvents.first(where: { $0.id == id })?.meetingURL else { return }
        openMeeting(url)
    }

    public func start() {
        guard observation == nil else { return }
        observation = Task { [weak self, service] in
            for await snapshot in await service.updates() {
                guard !Task.isCancelled, let self else { return }
                self.receive(snapshot)
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
        openMeeting(url)
        reminders.dismiss()
    }
    public func reminderBanner(action: @escaping @MainActor () -> Void) -> AnyView {
        AnyView(CalendarReminderView(model: self, openActivity: action))
    }
    public func homeCalendar(openCalendar: @escaping @MainActor () -> Void) -> AnyView {
        AnyView(HomeCalendarView(model: self, openCalendar: openCalendar))
    }
    public func expandedCalendar() -> AnyView { AnyView(CalendarActivityView(model: self)) }
}
