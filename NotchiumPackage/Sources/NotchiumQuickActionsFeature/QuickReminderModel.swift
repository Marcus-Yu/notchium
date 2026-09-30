import Combine
import Foundation
import OSLog
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumPersistence
import NotchiumServices
import Observation

@MainActor @Observable public final class QuickReminderModel {
    public var draft: ReminderDraft
    public private(set) var access: ReminderAccess = .notDetermined
    public private(set) var lists: [ReminderList] = []
    public private(set) var error: String?
    public private(set) var isBusy = false
    public let store: QuickActionStore
    @ObservationIgnored private let service: any ReminderService
    @ObservationIgnored private let workspace: any QuickActionWorkspace
    @ObservationIgnored private let notifications: NotificationCoordinator
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var sessionRevision = 0
    @ObservationIgnored private var editRevision = 0
    @ObservationIgnored private var accessObservation: AnyCancellable?

    public init(service: any ReminderService, workspace: any QuickActionWorkspace,
                store: QuickActionStore, notifications: NotificationCoordinator, clock: any AppClock, calendar: Calendar = .current) {
        self.service = service; self.workspace = workspace; self.store = store
        self.notifications = notifications; self.clock = clock; self.calendar = calendar
        draft = ReminderDraft(date: .distantPast)
    }
    @ObservationIgnored private let parser = ReminderNaturalLanguageParser()
    @ObservationIgnored private var referenceDate = Date.distantPast
    @ObservationIgnored private var appliedSignature: String?
    @ObservationIgnored private var manualSignature: String?
    @ObservationIgnored private var manualTimeEnabled = false

    public func prepare() async {
        accessObservation = service.changes.sink { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.accessObservation != nil else { return }
                self.refreshState()
            }
        }
        sessionRevision += 1
        let session = sessionRevision
        let now = await clock.now()
        guard session == sessionRevision, !Task.isCancelled else { return }
        referenceDate = now
        draft.date = referenceDate
        appliedSignature = nil
        manualSignature = nil
        manualTimeEnabled = false
        draft.includesTime = false
        applySuggestion(now: referenceDate)
        await refreshAccess(request: true)
        logValidation()
    }
    public func refreshAccess(request: Bool = false) async {
        error = nil
        refreshState()
        do {
            if request && access == .notDetermined { _ = try await service.requestAccess() }
            refreshState()
        } catch {
            refreshState()
            self.error = error.localizedDescription
        }
    }

    private func refreshState() {
        access = service.access()
        lists = access == .allowed ? service.lists() : []
        if access == .allowed && !store.reminderListID.isEmpty && !lists.contains(where: { $0.id == store.reminderListID }) {
            store.reminderListID = ""
        }
    }
    /// The view task debounces date/time updates; title validation remains immediate.
    func parseAfterDebounce() async {
        let text = draft.title
        let session = sessionRevision
        do { try await clock.sleep(for: .milliseconds(250)) } catch { return }
        let now = await clock.now()
        guard !Task.isCancelled, session == sessionRevision, draft.title == text else { return }
        applySuggestion(now: now)
    }

    func applySuggestion(now: Date) {
        referenceDate = now
        guard let suggestion = parser.parse(draft.title, now: now, calendar: calendar) else {
            appliedSignature = nil
            return
        }
        guard suggestion.signature != manualSignature else { return }
        // Recompute time-only suggestions on save so they cannot expire while composing.
        guard suggestion.signature != appliedSignature || !suggestion.hasDate else { return }
        editRevision += 1
        manualSignature = nil
        appliedSignature = suggestion.signature
        if suggestion.includesTime {
            draft.date = suggestion.date
            draft.includesTime = true
        } else {
            if !suggestion.preservesTime { draft.includesTime = manualTimeEnabled }
            let time = calendar.dateComponents([.hour, .minute], from: draft.date)
            draft.date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                       second: 0, of: suggestion.date) ?? suggestion.date
        }
    }

    private func markManualOverride() {
        editRevision += 1
        manualSignature = parser.parse(draft.title, now: referenceDate, calendar: calendar)?.signature
    }

    func setDate(_ date: Date) {
        markManualOverride()
        draft.date = date
    }

    @discardableResult
    func setIncludesTime(_ enabled: Bool) -> Int {
        markManualOverride()
        manualTimeEnabled = enabled
        draft.includesTime = enabled
        return editRevision
    }

    /// Only an explicit toggle requests a default time; parsing never calls this.
    func initializeManualTime(revision: Int) async {
        let session = sessionRevision
        let now = await clock.now()
        guard revision == editRevision, session == sessionRevision, draft.includesTime,
              manualTimeEnabled, !Task.isCancelled else { return }
        referenceDate = now
        let next = ReminderDraft.nextHalfHour(after: now, calendar: calendar)
        if calendar.isDate(draft.date, inSameDayAs: now) { draft.date = next }
        else {
            let time = calendar.dateComponents([.hour, .minute], from: next)
            draft.date = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0,
                                       second: 0, of: draft.date) ?? draft.date
        }
    }

    func saveCurrent() async -> Bool {
        guard canSaveReminder else { logValidation(); return false }
        isBusy = true
        defer { isBusy = false; logValidation() }
        let session = sessionRevision
        let now = await clock.now()
        guard session == sessionRevision, !Task.isCancelled else { return false }
        applySuggestion(now: now)
        refreshState()
        guard validationFailure == nil else { return false }
        return persist()
    }

    func endSession() {
        accessObservation = nil
        editRevision += 1
        sessionRevision += 1
    }

    var effectiveTitle: String {
        let raw = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        // A confidently parsed empty title is temporal-only, not a reminder title.
        return parser.parse(raw, now: referenceDate, calendar: calendar)?.title ?? raw
    }

    var selectedList: ReminderList? {
        lists.first { $0.id == store.reminderListID } ?? lists.first
    }

    private var validationFailure: String? {
        if effectiveTitle.isEmpty { return "emptyTitle" }
        if access != .allowed { return "permission" }
        if selectedList == nil { return "noWritableList" }
        guard draft.date.timeIntervalSinceReferenceDate.isFinite else { return "invalidDate" }
        let components = draft.dueComponents(timeZone: calendar.timeZone)
        guard components.isValidDate else { return "invalidDate" }
        if draft.includesTime && (components.hour == nil || components.minute == nil) { return "invalidTime" }
        return nil
    }

    var disableReason: String? { isBusy ? "saveInProgress" : validationFailure }
    public var canSaveReminder: Bool { disableReason == nil }

    func logValidation() {
        #if DEBUG
        let logger = Logger(subsystem: "Notchium", category: "QuickReminder")
        let authorization = switch access {
        case .allowed: "fullAccess"
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .restricted: "restricted"
        }
        let time = draft.dueComponents(timeZone: calendar.timeZone)
        logger.debug("authorization=\(authorization, privacy: .public) rawTitle=\(self.draft.title, privacy: .private) effectiveTitle=\(self.effectiveTitle, privacy: .private) dueDate=\(self.draft.date.description, privacy: .private) atTime=\(self.draft.includesTime) time=\(String(describing: time.hour), privacy: .private):\(String(describing: time.minute), privacy: .private) writableLists.count=\(self.lists.count) selectedList=\(self.selectedList?.id ?? "none", privacy: .private) isSaving=\(self.isBusy) canSaveReminder=\(self.canSaveReminder) disableReason=\(self.disableReason ?? "none", privacy: .public)")
        #endif
    }

    private func persist() -> Bool {
        do {
            var savedDraft = draft
            savedDraft.title = effectiveTitle
            try service.save(savedDraft, listID: selectedList?.id)
            draft.title = ""; error = nil
            notifications.present(.feedback("Reminder Added", kind: .reminderAdded, key: "reminder.added"))
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    public func openPrivacy() { workspace.openReminderPrivacy() }
    public func cancel() { endSession(); draft.title = ""; error = nil }
}
