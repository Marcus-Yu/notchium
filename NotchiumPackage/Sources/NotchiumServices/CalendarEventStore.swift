import EventKit
import Foundation

/// Keeps EventKit I/O inside the service boundary and permits permission recovery tests
/// without requesting access to, or reading, the user's calendars.
@MainActor
protocol CalendarEventStoreAccessing: AnyObject {
    var authorizationStatus: EKAuthorizationStatus { get }
    func requestFullAccess() async throws -> Bool
    func reset()
    func calendars() -> [EKCalendar]
    func events(from start: Date, to end: Date, calendars: [EKCalendar]) -> [EKEvent]
}

@MainActor
final class EventKitCalendarStore: CalendarEventStoreAccessing {
    private let store = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    func requestFullAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
    func reset() { store.reset() }
    func calendars() -> [EKCalendar] { store.calendars(for: .event) }
    func events(from start: Date, to end: Date, calendars: [EKCalendar]) -> [EKEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
    }
}
