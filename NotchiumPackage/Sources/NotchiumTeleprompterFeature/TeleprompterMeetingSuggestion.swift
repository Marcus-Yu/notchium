import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation

/// A quiet, reversible suggestion. Calendar timing never proves a call by itself.
@MainActor @Observable
public final class TeleprompterMeetingSuggestion {
    public private(set) var isSuggested = false
    @ObservationIgnored private let context: any TeleprompterMeetingContextService
    @ObservationIgnored private let calendar: any CalendarService
    @ObservationIgnored private let activities: ActivityCoordinator
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private let uuids: any UUIDGenerating
    @ObservationIgnored private var contextTask: Task<Void, Never>?
    @ObservationIgnored private var calendarTask: Task<Void, Never>?
    @ObservationIgnored private var currentContext: TeleprompterMeetingContext = .idle
    @ObservationIgnored private var events: [CalendarEventSummary] = []
    private static let key = NotchActivityKey("teleprompter.meetingSuggestion")

    public init(context: any TeleprompterMeetingContextService, calendar: any CalendarService,
                activities: ActivityCoordinator, clock: any AppClock, uuids: any UUIDGenerating) {
        self.context = context; self.calendar = calendar; self.activities = activities
        self.clock = clock; self.uuids = uuids
    }

    public func start() {
        guard contextTask == nil else { return }
        contextTask = Task { [weak self, context] in
            for await value in await context.updates() {
                guard !Task.isCancelled, let self else { return }
                self.currentContext = value
                await self.update()
            }
        }
        calendarTask = Task { [weak self, calendar] in
            for await snapshot in await calendar.updates() {
                guard !Task.isCancelled, let self else { return }
                self.events = snapshot.upcomingEvents
                await self.update()
            }
        }
    }

    public func stop() {
        contextTask?.cancel(); contextTask = nil
        calendarTask?.cancel(); calendarTask = nil
        currentContext = .idle
        events = []
        isSuggested = false
        activities.dismiss(key: Self.key)
    }

    private func update() async {
        let now = await clock.now()
        guard !Task.isCancelled else { return }
        let suggested: Bool
        switch currentContext {
        case .probableCall: suggested = true
        case .browserUsingInput:
            suggested = events.contains { !$0.isAllDay && $0.meetingURL != nil && $0.startDate <= now && now < $0.endDate }
        case .idle, .unavailable: suggested = false
        }
        guard suggested != isSuggested else { return }
        isSuggested = suggested
        if suggested {
            let id = await uuids.next()
            guard !Task.isCancelled, isSuggested else { return }
            activities.present(.init(id: id, key: Self.key, kind: .meeting,
                title: "Teleprompter available", subtitle: nil, priority: .low,
                presentationStyle: NotchActivityPresentationStyle.none, lifetime: .condition, destination: .teleprompter,
                timestamp: now, duration: nil))
        } else { activities.dismiss(key: Self.key) }
    }

    isolated deinit {
        contextTask?.cancel()
        calendarTask?.cancel()
    }
}
