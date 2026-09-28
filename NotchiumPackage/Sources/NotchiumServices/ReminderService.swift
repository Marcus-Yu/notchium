import AppKit
import Combine
import EventKit
import Foundation
import NotchiumCore

public enum ReminderFailure: LocalizedError, Equatable {
    case permission, noWritableList, emptyTitle
    public var errorDescription: String? {
        switch self {
        case .permission: "Allow Notchium to access Reminders in System Settings → Privacy & Security → Reminders."
        case .noWritableList: "Create a writable list in Reminders, then try again."
        case .emptyTitle: "Enter a reminder."
        }
    }
}

@MainActor public protocol ReminderService: Sendable {
    var changes: AnyPublisher<Void, Never> { get }
    func access() -> ReminderAccess
    func requestAccess() async throws -> ReminderAccess
    func lists() -> [ReminderList]
    func save(_ draft: ReminderDraft, listID: String?) throws
}

public extension ReminderService {
    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
}

/// EventKit objects remain confined to this adapter. No calendar event is created.
@MainActor public final class EventKitReminderService: ReminderService {
    private let store: EKEventStore
    public init() { store = EKEventStore() }
    public var changes: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
            .map { _ in () }.eraseToAnyPublisher()
    }
    public func access() -> ReminderAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .allowed
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        default: .denied
        }
    }
    public func requestAccess() async throws -> ReminderAccess {
        if access() == .notDetermined { _ = try await store.requestFullAccessToReminders() }
        return access()
    }
    private var writable: [EKCalendar] {
        guard access() == .allowed else { return [] }
        return store.calendars(for: .reminder).filter(\.allowsContentModifications)
    }
    public func lists() -> [ReminderList] {
        guard access() == .allowed else { return [] }
        let calendars = writable
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        // Keep the system default first so validation and saving resolve the same fallback.
        return (calendars.filter { $0.calendarIdentifier == defaultID }
            + calendars.filter { $0.calendarIdentifier != defaultID })
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
    }
    public func save(_ draft: ReminderDraft, listID: String?) throws {
        guard access() == .allowed else { throw ReminderFailure.permission }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ReminderFailure.emptyTitle }
        let lists = writable
        let systemDefault = store.defaultCalendarForNewReminders()
        guard let list = lists.first(where: { $0.calendarIdentifier == listID })
            ?? lists.first(where: { $0.calendarIdentifier == systemDefault?.calendarIdentifier })
            ?? lists.first else { throw ReminderFailure.noWritableList }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        reminder.dueDateComponents = draft.dueComponents()
        try store.save(reminder, commit: true)
    }
}

@MainActor public final class MockReminderService: ReminderService {
    private let changeSubject = PassthroughSubject<Void, Never>()
    public var changes: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }
    public func notifyChanges() { changeSubject.send() }
    public var authorization: ReminderAccess = .allowed
    public var availableLists = [ReminderList(id: "personal", title: "Personal")]
    public var failure: ReminderFailure?
    public private(set) var saved: [ReminderDraft] = []
    public private(set) var requestCount = 0
    public init() {}
    public func access() -> ReminderAccess { authorization }
    public func requestAccess() async throws -> ReminderAccess { requestCount += 1; return authorization }
    public func lists() -> [ReminderList] { authorization == .allowed ? availableLists : [] }
    public func save(_ draft: ReminderDraft, listID: String?) throws {
        if let failure { throw failure }
        guard authorization == .allowed else { throw ReminderFailure.permission }
        guard !availableLists.isEmpty else { throw ReminderFailure.noWritableList }
        saved.append(draft)
    }
}
