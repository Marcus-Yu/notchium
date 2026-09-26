import AppKit
import EventKit
import Foundation
import NotchiumCore

public enum CalendarPermission: Sendable, Equatable {
    case notRequested, granted, denied, restricted
}

public struct MonitoredCalendar: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let color: CalendarColor
    public let isSelected: Bool

    public init(id: String, name: String, color: CalendarColor, isSelected: Bool) {
        self.id = id; self.name = name; self.color = color; self.isSelected = isSelected
    }
}

public struct CalendarColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
}

public enum CalendarEventStatus: Equatable, Sendable {
    case upcoming, startingSoon, now, inProgress, ended

    public static let approachingInterval: TimeInterval = 15 * 60
    public static let nowInterval: TimeInterval = 60

    public static func status(start: Date, end: Date, at date: Date) -> Self {
        if date >= end { return .ended }
        if date >= start.addingTimeInterval(nowInterval) { return .inProgress }
        if date >= start { return .now }
        if start.timeIntervalSince(date) <= approachingInterval { return .startingSoon }
        return .upcoming
    }
}

public struct CalendarEventSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let location: String?
    public let calendarName: String
    public let calendarColor: CalendarColor
    public let meetingURL: URL?
    public let isAllDay: Bool

    public init(id: UUID, title: String, startDate: Date, endDate: Date,
                meetingURL: URL? = nil, location: String? = nil,
                calendarName: String = "Calendar",
                calendarColor: CalendarColor = .init(red: 0.55, green: 0.65, blue: 0.95),
                isAllDay: Bool = false) {
        self.id = id; self.title = title; self.startDate = startDate; self.endDate = endDate
        self.meetingURL = meetingURL; self.location = location
        self.calendarName = calendarName; self.calendarColor = calendarColor; self.isAllDay = isAllDay
    }

    public func status(at date: Date) -> CalendarEventStatus {
        CalendarEventStatus.status(start: startDate, end: endDate, at: date)
    }
}

public struct CalendarSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let permission: CalendarPermission
    public let calendars: [MonitoredCalendar]
    public let upcomingEvents: [CalendarEventSummary]
    public var nextEvent: CalendarEventSummary? { upcomingEvents.first }

    public init(availability: FeatureAvailability, upcomingEvents: [CalendarEventSummary] = [],
                permission: CalendarPermission = .granted, calendars: [MonitoredCalendar] = []) {
        self.availability = availability; self.upcomingEvents = upcomingEvents
        self.permission = permission; self.calendars = calendars
    }
}

public protocol CalendarService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<CalendarSnapshot>
    func refresh() async throws
    func requestAccess() async
    func setCalendarSelected(_ id: String, selected: Bool) async
    func stop() async
}

@MainActor
public final class RealCalendarService: CalendarService {
    private let store = EKEventStore()
    private let selectionKey = "notchium.calendar.selectedIdentifiers"
    private var continuations: [UUID: AsyncStream<CalendarSnapshot>.Continuation] = [:]
    private var latest = CalendarSnapshot(availability: .unavailable(.permissionNotDetermined),
                                          permission: .notRequested)
    private var eventIDs: [String: UUID] = [:]
    private var boundaryTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var started = false

    public init() {}

    public func availability() async -> FeatureAvailability {
        return switch permission {
        case .granted: .available
        case .notRequested: .unavailable(.permissionNotDetermined)
        case .denied: .unavailable(.permissionDenied)
        case .restricted: .unavailable(.permissionRestricted)
        }
    }

    public func updates() async -> AsyncStream<CalendarSnapshot> {
        if !started { startObserving(); refreshNow() }
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(latest)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    public func refresh() async throws { refreshNow() }

    public func requestAccess() async {
        guard permission == .notRequested else { refreshNow(); return }
        _ = try? await store.requestFullAccessToEvents()
        refreshNow()
    }

    public func setCalendarSelected(_ id: String, selected: Bool) async {
        guard permission == .granted else { return }
        let valid = Set(store.calendars(for: .event).map(\.calendarIdentifier))
        guard valid.contains(id) else { return }
        var ids = selectedIDs(valid: valid)
        if selected { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(Array(ids).sorted(), forKey: selectionKey)
        refreshNow()
    }

    public func stop() async {
        boundaryTask?.cancel(); boundaryTask = nil
        changeTask?.cancel(); changeTask = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        continuations.removeAll()
        started = false
    }

    private var permission: CalendarPermission {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notRequested
        case .fullAccess, .authorized: .granted
        case .denied, .writeOnly: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    private func startObserving() {
        started = true
        let center = NotificationCenter.default
        for name in [Notification.Name.EKEventStoreChanged, .NSCalendarDayChanged,
                     NSApplication.didBecomeActiveNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let observerCenter = (name == NSWorkspace.didWakeNotification || name == NSWorkspace.screensDidWakeNotification)
                ? NSWorkspace.shared.notificationCenter : center
            let token = observerCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleRefresh() }
            }
            observers.append((observerCenter, token))
        }
    }

    private func scheduleRefresh() {
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.refreshNow()
        }
    }

    private func selectedIDs(valid: Set<String>) -> Set<String> {
        if let saved = UserDefaults.standard.stringArray(forKey: selectionKey) {
            return Set(saved).intersection(valid)
        }
        // Initial grant monitors the calendars configured in Calendar.app.
        UserDefaults.standard.set(Array(valid).sorted(), forKey: selectionKey)
        return valid
    }

    private func refreshNow() {
        boundaryTask?.cancel()
        let state = permission
        guard state == .granted else {
            let reason: AvailabilityReason = state == .notRequested ? .permissionNotDetermined
                : state == .denied ? .permissionDenied : .permissionRestricted
            publish(.init(availability: .unavailable(reason), permission: state))
            return
        }

        let all = store.calendars(for: .event)
        let ids = selectedIDs(valid: Set(all.map(\.calendarIdentifier)))
        let calendars = all.map { calendar in
            MonitoredCalendar(id: calendar.calendarIdentifier, name: calendar.title,
                              color: Self.color(calendar), isSelected: ids.contains(calendar.calendarIdentifier))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let now = Date.now
        let selected = all.filter { ids.contains($0.calendarIdentifier) }
        var events: [CalendarEventSummary] = []
        var currentIDs: [String: UUID] = [:]
        if !selected.isEmpty {
            let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-86_400),
                end: now.addingTimeInterval(14 * 86_400), calendars: selected)
            for event in store.events(matching: predicate)
                where event.endDate > now && event.status != .canceled {
                let key = "\(event.calendar.calendarIdentifier):\(event.eventIdentifier ?? ""):\(event.startDate.timeIntervalSince1970)"
                let id = eventIDs[key] ?? UUID()
                currentIDs[key] = id
                events.append(.init(id: id, title: event.title?.isEmpty == false ? event.title : "Untitled event",
                    startDate: event.startDate, endDate: event.endDate,
                    meetingURL: MeetingLinkDetector.detect(url: event.url, location: event.location, notes: event.notes),
                    location: event.location?.nilIfBlank,
                    calendarName: event.calendar.title, calendarColor: Self.color(event.calendar),
                    isAllDay: event.isAllDay))
            }
        }
        eventIDs = currentIDs
        events.sort { $0.startDate == $1.startDate ? $0.endDate < $1.endDate : $0.startDate < $1.startDate }
        publish(.init(availability: .available, upcomingEvents: events,
                      permission: .granted, calendars: calendars))
        scheduleBoundary(for: events, at: now)
    }

    private func publish(_ snapshot: CalendarSnapshot) {
        latest = snapshot
        for continuation in continuations.values { continuation.yield(snapshot) }
    }

    private func scheduleBoundary(for events: [CalendarEventSummary], at now: Date) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let dates = events.flatMap { event in
            [event.startDate.addingTimeInterval(-CalendarEventStatus.approachingInterval),
             event.startDate, event.startDate.addingTimeInterval(CalendarEventStatus.nowInterval), event.endDate]
        }
        guard let next = (dates + [tomorrow]).filter({ $0 > now }).min() else { return }
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.1, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.refreshNow()
        }
    }

    private static func color(_ calendar: EKCalendar) -> CalendarColor {
        let color = NSColor(cgColor: calendar.cgColor)?.usingColorSpace(.deviceRGB) ?? .systemBlue
        return .init(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent))
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

public enum MeetingLinkDetector {
    private static let pattern = try! NSRegularExpression(pattern: #"https://[^\s<>\"']+"#, options: [.caseInsensitive])

    public static func detect(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isSupported(url) { return url }
        for text in [location, notes].compactMap({ $0 }) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let stringRange = Range(match.range, in: text) else { continue }
                let raw = String(text[stringRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]}"))
                if let candidate = URL(string: raw), isSupported(candidate) { return candidate }
            }
        }
        return nil
    }

    public static func isSupported(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", let host = components.host?.lowercased(),
              components.user == nil, components.password == nil else { return false }
        let path = components.path.lowercased()
        if host == "meet.google.com" {
            return path.hasPrefix("/lookup/") || path.range(
                of: #"^/[a-z]{3}-[a-z]{4}-[a-z]{3}/?$"#, options: .regularExpression) != nil
        }
        if host == "teams.microsoft.com" || host == "teams.live.com"
            || host == "teams.cloud.microsoft" {
            return path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/")
        }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return path.hasPrefix("/j/") || path.hasPrefix("/my/")
                || path.hasPrefix("/wc/join/")
        }
        return false
    }
}

public struct MockCalendarService: CalendarService {
    public let snapshot: CalendarSnapshot
    public init(snapshot: CalendarSnapshot = CalendarSnapshot(availability: .available)) { self.snapshot = snapshot }
    public func availability() async -> FeatureAvailability { snapshot.availability }
    public func updates() async -> AsyncStream<CalendarSnapshot> { oneShotStream(snapshot) }
    public func refresh() async throws {}
    public func requestAccess() async {}
    public func setCalendarSelected(_ id: String, selected: Bool) async {}
    public func stop() async {}
}
