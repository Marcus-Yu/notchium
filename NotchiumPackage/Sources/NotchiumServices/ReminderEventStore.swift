import EventKit
import Foundation
import NotchiumCore

/// Native objects stay inside this adapter; tests never need personal reminder access.
@MainActor
protocol ReminderEventStoreAccessing: AnyObject {
    var authorizationStatus: EKAuthorizationStatus { get }
    func requestFullAccess() async throws -> Bool
    func reset()
    func lists() -> [ReminderList]
    func save(_ draft: ReminderDraft, listID: String?) throws
}

@MainActor
final class EventKitReminderStore: ReminderEventStoreAccessing {
    private let store = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }
    func requestFullAccess() async throws -> Bool { try await store.requestFullAccessToReminders() }
    func reset() { store.reset() }

    private var writable: [EKCalendar] {
        store.calendars(for: .reminder).filter(\.allowsContentModifications)
    }

    func lists() -> [ReminderList] {
        let calendars = writable
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        // Keep the system default first so validation and saving share the fallback.
        return (calendars.filter { $0.calendarIdentifier == defaultID }
            + calendars.filter { $0.calendarIdentifier != defaultID })
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
    }

    func save(_ draft: ReminderDraft, listID: String?) throws {
        let calendars = writable
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        guard let list = calendars.first(where: { $0.calendarIdentifier == listID })
            ?? calendars.first(where: { $0.calendarIdentifier == defaultID })
            ?? calendars.first else { throw ReminderFailure.noWritableList }
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.calendar = list
        reminder.dueDateComponents = draft.dueComponents()
        try store.save(reminder, commit: true)
    }
}
