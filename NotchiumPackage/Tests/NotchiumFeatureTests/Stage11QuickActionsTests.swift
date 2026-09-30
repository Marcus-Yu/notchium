import AppKit
import SwiftUI
import XCTest
import NotchiumCore
import NotchiumPersistence
import NotchiumServices
@testable import NotchiumDynamicIsland
@testable import NotchiumQuickActionsFeature

@MainActor final class Stage11QuickActionsTests: XCTestCase {
    private var preferences: UserDefaults!
    private var suite: String!
    private let date = Date(timeIntervalSince1970: 1_790_511_120)
    override func setUp() async throws {
        suite = "Stage11.\(UUID())"
        preferences = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws { preferences.removePersistentDomain(forName: suite) }

    func testDateOnlyAndTimedReminderComponents() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: -4 * 3600))
        let allDay = ReminderDraft(title: "Call dentist", date: date).dueComponents(timeZone: zone)
        XCTAssertNotNil(allDay.year); XCTAssertNotNil(allDay.month); XCTAssertNotNil(allDay.day)
        XCTAssertNil(allDay.hour); XCTAssertNil(allDay.minute); XCTAssertNil(allDay.timeZone)
        XCTAssertEqual(allDay.calendar?.identifier, .gregorian)
        let timed = ReminderDraft(title: "Call dentist", date: date, includesTime: true).dueComponents(timeZone: zone)
        XCTAssertNotNil(timed.hour); XCTAssertNotNil(timed.minute); XCTAssertEqual(timed.timeZone, zone)
    }

    func testHalfHourBoundaryAndMidnightRollover() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        for (hour, minute, expectedHour, expectedMinute) in [(14, 12, 14, 30), (14, 42, 15, 0), (23, 42, 0, 0), (14, 30, 15, 0)] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: hour, minute: minute)))
            let next = ReminderDraft.nextHalfHour(after: date, calendar: calendar)
            XCTAssertEqual(calendar.component(.hour, from: next), expectedHour)
            XCTAssertEqual(calendar.component(.minute, from: next), expectedMinute)
            XCTAssertGreaterThan(next, date)
        }
    }

    func testStoreDefaultOffPersistenceReorderAndPinLimit() throws {
        let store = QuickActionStore(preferences: preferences)
        XCTAssertFalse(store.showOnHome)
        let actions = (0..<5).map { QuickAction(kind: .url, displayName: "Site \($0)", target: "https://example.com", pinnedToHome: $0 < 4) }
        for action in actions { try store.save(action) }
        var fifth = actions[4]; fifth.pinnedToHome = true
        XCTAssertThrowsError(try store.save(fifth))
        XCTAssertEqual(store.pinned.count, 4)
        try store.move(from: IndexSet(integer: 4), to: 0)
        XCTAssertEqual(store.actions.first?.id, fifth.id)
        store.showOnHome = true
        let restored = QuickActionStore(preferences: preferences)
        XCTAssertTrue(restored.showOnHome)
        XCTAssertEqual(restored.actions, store.actions)
        try store.remove(actions[0].id)
        try store.save(fifth)
        XCTAssertEqual(store.pinned.count, 4)
    }

    func testMalformedPersistenceIsNotOverwritten() {
        preferences.set(Data("broken".utf8), forKey: "quickActions.v1")
        let store = QuickActionStore(preferences: preferences)
        XCTAssertNotNil(store.error)
        XCTAssertThrowsError(try store.save(QuickAction(kind: .url)))
        XCTAssertEqual(preferences.data(forKey: "quickActions.v1"), Data("broken".utf8))
    }

    func testURLValidationRejectsExecutablesAndCredentials() {
        XCTAssertNotNil(QuickAction.validatedWebURL("https://example.com/path?q=test"))
        for target in ["file:///tmp/a", "javascript:alert(1)", "shortcuts://run-shortcut", "https://", "https://user:secret@example.com"] {
            XCTAssertNil(QuickAction.validatedWebURL(target))
        }
    }

    func testShortcutParserUsesLastIdentifierAndRejectsMalformedOutput() throws {
        let id = UUID()
        let parsed = try AppleShortcutService.parseList("Name (with parentheses) (\(id))\n")
        XCTAssertEqual(parsed, [ExistingShortcut(id: id, name: "Name (with parentheses)")])
        XCTAssertThrowsError(try AppleShortcutService.parseList("Malformed (identifier)"))
    }

    func testRenamedDeletedAndReusedShortcutNamesCannotRun() async throws {
        let original = ExistingShortcut(id: UUID(), name: "Morning")
        let service = MockShortcutService(shortcuts: [original])
        try await service.run(original)
        await service.setShortcuts([ExistingShortcut(id: original.id, name: "Renamed"), ExistingShortcut(id: UUID(), name: "Morning")])
        do { try await service.run(original); XCTFail("Must not execute a renamed shortcut or reused name") }
        catch { XCTAssertEqual(error as? QuickActionFailure, .shortcutMissing) }
        let executions = await service.executions
        XCTAssertEqual(executions, [original])
    }

    func testReminderPermissionIsContextualAndFailureRetainsDraft() async throws {
        let service = MockReminderService()
        let (model, presentation) = fixture(reminders: service)
        XCTAssertEqual(service.requestCount, 0)
        await model.reminder.prepare()
        XCTAssertEqual(model.reminder.draft.date, date)
        XCTAssertFalse(model.reminder.draft.includesTime)
        model.reminder.draft.title = "Call dentist"
        service.failure = .noWritableList
        let saved1 = await model.reminder.saveCurrent()
        XCTAssertFalse(saved1)
        XCTAssertEqual(model.reminder.draft.title, "Call dentist")
        XCTAssertNil(presentation.notificationCoordinator.active)
        service.failure = nil
        let saved2 = await model.reminder.saveCurrent()
        XCTAssertTrue(saved2)
        XCTAssertEqual(service.saved.count, 1)
        XCTAssertEqual(model.reminder.draft.title, "")
        XCTAssertEqual(presentation.notificationCoordinator.active?.duration, .seconds(2))
        presentation.reset()
    }

    func testDeniedRemindersCannotSaveAndListFallbackOnlyAfterAccess() async {
        let service = MockReminderService(); service.authorization = .denied
        let (model, presentation) = fixture(reminders: service)
        model.store.reminderListID = "deleted-list"
        await model.reminder.prepare()
        model.reminder.draft.title = "Keep this"
        let saved3 = await model.reminder.saveCurrent()
        XCTAssertFalse(saved3)
        XCTAssertEqual(model.store.reminderListID, "deleted-list")
        XCTAssertEqual(service.saved.count, 0)
        service.authorization = .allowed
        await model.reminder.refreshAccess()
        XCTAssertEqual(model.store.reminderListID, "")
        model.reminder.cancel()
        XCTAssertEqual(model.reminder.draft.title, "")
        presentation.reset()
    }

    func testFeedbackIsLowPriorityCoalescedAndDoesNotChangePage() {
        let (_, presentation) = fixture()
        presentation.setExpanded(true)
        presentation.pageModel.selectedPage = .home
        let coordinator = presentation.notificationCoordinator
        let success = NotchNotification.feedback("Opened", kind: .actionSucceeded, key: "same")
        XCTAssertTrue(coordinator.present(success))
        XCTAssertEqual(coordinator.active?.duration, .milliseconds(1500))
        XCTAssertEqual(coordinator.active?.priority, .low)
        XCTAssertNil(success.activity.destination)
        XCTAssertTrue(coordinator.present(.feedback("Opened", kind: .actionSucceeded, key: "same")))
        XCTAssertEqual(coordinator.active?.id, success.id)
        XCTAssertEqual(presentation.pageModel.selectedPage, .home)
        coordinator.present(.init(kind: .reminder5, coalescingKey: "calendar", action: .calendar,
            presentationStyle: .calendar, content: .calendar(title: "Meeting", status: "Soon")))
        XCTAssertFalse(coordinator.present(success))
        XCTAssertEqual(coordinator.active?.kind, .reminder5)
        XCTAssertEqual(NotchNotification.Kind.actionFailed.defaultDuration, .seconds(3))
        presentation.reset()
    }

    func testNativeActionsUseWorkspaceAndBrokenConfigurationIsRetained() async throws {
        let workspace = Stage11Workspace()
        let (model, presentation) = fixture(workspace: workspace)
        for kind in [QuickActionKind.application, .file, .folder, .url] {
            let action = QuickAction(kind: kind, displayName: kind.title, target: "https://example.com")
            try model.store.save(action)
            model.runner.run(action)
            for _ in 0..<1000 where model.runner.running.contains(action.id) { await Task.yield() }
        }
        XCTAssertEqual(workspace.opened.count, 4)
        workspace.fail = true
        let action = try XCTUnwrap(model.store.actions.first)
        model.runner.run(action)
        for _ in 0..<1000 where model.runner.running.contains(action.id) { await Task.yield() }
        XCTAssertNotNil(model.runner.unavailable[action.id])
        XCTAssertEqual(model.store.actions.count, 4)
        presentation.reset(); model.runner.stop()
    }

    func testReminderParsingManualOverrideAndCleanSave() async throws {
        let service = MockReminderService()
        let (model, presentation) = fixture(reminders: service)
        defer { presentation.reset() }
        let reminder = model.reminder
        await reminder.prepare()
        reminder.draft.title = "test friday 3:00pm"
        reminder.applySuggestion(now: date)
        XCTAssertTrue(reminder.draft.includesTime)
        XCTAssertEqual(Calendar.current.component(.hour, from: reminder.draft.date), 15)
        XCTAssertEqual(reminder.draft.title, "test friday 3:00pm")
        let saturday = Calendar.current.date(byAdding: .day, value: 1, to: reminder.draft.date)!
        reminder.setDate(saturday)
        reminder.draft.title = "updated test friday 3:00pm"
        reminder.applySuggestion(now: date)
        XCTAssertEqual(reminder.draft.date, saturday)
        let saved4 = await reminder.saveCurrent()
        XCTAssertTrue(saved4)
        XCTAssertEqual(service.saved.last?.title, "updated test")
        XCTAssertEqual(service.saved.last?.date, saturday)
        XCTAssertEqual(service.saved.count, 1)
    }

    func testChangedTemporalPhraseReleasesManualOverrideAndDateOnlyKeepsManualTime() async {
        let (model, presentation) = fixture()
        defer { presentation.reset() }
        let reminder = model.reminder
        await reminder.prepare()
        reminder.draft.title = "test friday 3pm"
        reminder.applySuggestion(now: date)
        reminder.setIncludesTime(false)
        reminder.applySuggestion(now: date)
        XCTAssertFalse(reminder.draft.includesTime)
        reminder.draft.title = "test friday 4pm"
        reminder.applySuggestion(now: date)
        XCTAssertTrue(reminder.draft.includesTime)
        XCTAssertEqual(Calendar.current.component(.hour, from: reminder.draft.date), 16)
        reminder.draft.title = "test tomorrow"
        reminder.applySuggestion(now: date)
        XCTAssertFalse(reminder.draft.includesTime)
        reminder.setIncludesTime(true)
        reminder.draft.title = "test friday"
        reminder.applySuggestion(now: date)
        XCTAssertTrue(reminder.draft.includesTime)
    }

    func testImmediateSaveParsesAndFailurePreservesInput() async {
        let service = MockReminderService()
        let (model, presentation) = fixture(reminders: service)
        defer { presentation.reset() }
        await model.reminder.prepare()
        model.reminder.draft.title = "call tomorrow at 9am"
        service.failure = .noWritableList
        let saved5 = await model.reminder.saveCurrent()
        XCTAssertFalse(saved5)
        XCTAssertEqual(model.reminder.draft.title, "call tomorrow at 9am")
        service.failure = nil
        let saved6 = await model.reminder.saveCurrent()
        XCTAssertTrue(saved6)
        XCTAssertEqual(service.saved.last?.title, "call")
        XCTAssertEqual(Calendar.current.component(.hour, from: service.saved.last!.date), 9)
    }

    func testDebounceCancellationAndManualEditBeforePendingParse() async {
        let clock = TestAppClock(now: date, automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        defer { presentation.reset() }
        let reminder = QuickReminderModel(service: MockReminderService(), workspace: Stage11Workspace(),
            store: QuickActionStore(preferences: preferences), notifications: presentation.notificationCoordinator, clock: clock)
        await reminder.prepare()
        reminder.draft.title = "test friday 3pm"
        let cancelled = Task { await reminder.parseAfterDebounce() }
        await clock.waitForPendingSleeps()
        cancelled.cancel()
        await cancelled.value
        XCTAssertFalse(reminder.draft.includesTime)
        let pending = Task { await reminder.parseAfterDebounce() }
        await clock.waitForPendingSleeps()
        reminder.setDate(date)
        await clock.advance(by: .milliseconds(250))
        await pending.value
        XCTAssertEqual(reminder.draft.date, date)
        XCTAssertFalse(reminder.draft.includesTime)
    }

    func testFormattingAndTemporaryUnparsedTextPreserveManualOverride() async {
        let (model, presentation) = fixture()
        defer { presentation.reset() }
        await model.reminder.prepare()
        model.reminder.draft.title = "test friday 3pm"
        model.reminder.applySuggestion(now: date)
        model.reminder.setDate(date)
        model.reminder.draft.title = "test friday 3:"
        model.reminder.applySuggestion(now: date)
        model.reminder.draft.title = "test friday 3:00 pm"
        model.reminder.applySuggestion(now: date)
        XCTAssertEqual(model.reminder.draft.date, date)
    }

    func testInvalidTimeDoesNotDisableExistingManualTime() async {
        let (model, presentation) = fixture()
        defer { presentation.reset() }
        await model.reminder.prepare()
        model.reminder.setIncludesTime(true)
        model.reminder.setDate(date)
        model.reminder.draft.title = "test friday 37pm"
        model.reminder.applySuggestion(now: date)
        XCTAssertTrue(model.reminder.draft.includesTime)
        XCTAssertEqual(Calendar.current.component(.hour, from: model.reminder.draft.date), Calendar.current.component(.hour, from: date))
        XCTAssertEqual(Calendar.current.component(.weekday, from: model.reminder.draft.date), 6)
    }

    func testManualTimeUsesFreshClockAndStaleInitializationIsIgnored() async {
        let clock = TestAppClock(now: date, automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        defer { presentation.reset() }
        let reminder = QuickReminderModel(service: MockReminderService(), workspace: Stage11Workspace(),
            store: QuickActionStore(preferences: preferences), notifications: presentation.notificationCoordinator, clock: clock)
        await reminder.prepare()
        await clock.advance(by: .seconds(7200))
        let revision = reminder.setIncludesTime(true)
        await reminder.initializeManualTime(revision: revision)
        XCTAssertEqual(reminder.draft.date, ReminderDraft.nextHalfHour(after: date.addingTimeInterval(7200)))
        let stale = reminder.setIncludesTime(true)
        reminder.setDate(date)
        await reminder.initializeManualTime(revision: stale)
        XCTAssertEqual(reminder.draft.date, date)
        let pending = reminder.setIncludesTime(true)
        reminder.endSession()
        await reminder.initializeManualTime(revision: pending)
        XCTAssertEqual(reminder.draft.date, date)
    }

    func testAddAcceptanceTitlesAndDueDates() async throws {
        let service = MockReminderService()
        let (model, presentation) = fixture(reminders: service)
        defer { presentation.reset(); model.reminder.endSession() }
        for (raw, effective, hour, minute) in [
            ("test friday 1:00pm", "test", 13, 0),
            ("call dentist tomorrow 10:30am", "call dentist", 10, 30),
            ("buy milk", "buy milk", -1, -1)
        ] {
            await model.reminder.prepare()
            model.reminder.draft.title = raw
            // Button validation must work before the parsing debounce fires.
            XCTAssertTrue(model.reminder.canSaveReminder, model.reminder.disableReason ?? "")
            XCTAssertEqual(model.reminder.effectiveTitle, effective)
            let saved = await model.reminder.saveCurrent()
            XCTAssertTrue(saved)
            let draft = try XCTUnwrap(service.saved.last)
            XCTAssertEqual(draft.title, effective)
            if hour >= 0 {
                XCTAssertTrue(draft.includesTime)
                XCTAssertEqual(Calendar.current.component(.hour, from: draft.date), hour)
                XCTAssertEqual(Calendar.current.component(.minute, from: draft.date), minute)
            } else { XCTAssertFalse(draft.includesTime) }
        }
        XCTAssertEqual(service.saved.count, 3)
        XCTAssertEqual(Calendar.current.component(.weekday, from: service.saved[0].date), 6)
        XCTAssertTrue(Calendar.current.isDate(service.saved[1].date, inSameDayAs: Calendar.current.date(byAdding: .day, value: 1, to: date)!))
        for text in ["friday 1pm", "tomorrow", "   ", ""] {
            model.reminder.draft.title = text
            XCTAssertFalse(model.reminder.canSaveReminder)
            XCTAssertEqual(model.reminder.disableReason, "emptyTitle")
            let saved = await model.reminder.saveCurrent()
            XCTAssertFalse(saved)
        }
        XCTAssertEqual(service.saved.count, 3)
    }

    func testPermissionGrantLoadsListsImmediatelyAndIsReusedAcrossSessions() async {
        let service = MockReminderService()
        service.authorization = .notDetermined
        service.authorizationAfterRequest = .allowed
        let (model, presentation) = fixture(reminders: service)
        defer { presentation.reset(); model.reminder.endSession() }
        model.store.reminderListID = "deleted-list"
        await model.reminder.prepare()
        model.reminder.draft.title = "presentation tuesday 6:00 pm"
        model.reminder.applySuggestion(now: date)
        XCTAssertEqual(model.reminder.access, .allowed)
        XCTAssertEqual(model.reminder.selectedList?.id, "personal")
        XCTAssertEqual(model.reminder.effectiveTitle, "presentation")
        XCTAssertTrue(model.reminder.canSaveReminder)
        XCTAssertEqual(Calendar.current.component(.weekday, from: model.reminder.draft.date), 3)
        XCTAssertEqual(Calendar.current.component(.hour, from: model.reminder.draft.date), 18)
        XCTAssertEqual(Calendar.current.component(.minute, from: model.reminder.draft.date), 0)
        for _ in 0..<3 {
            model.reminder.endSession()
            await model.reminder.prepare()
            XCTAssertTrue(model.reminder.canSaveReminder)
        }
        // A new model has no cached permission, just as after relaunch.
        let (relaunched, secondPresentation) = fixture(reminders: service)
        defer { secondPresentation.reset(); relaunched.reminder.endSession() }
        await relaunched.reminder.prepare()
        relaunched.reminder.draft.title = "buy milk"
        XCTAssertTrue(relaunched.reminder.canSaveReminder)
        XCTAssertEqual(service.requestCount, 1)
    }

    func testDeniedAndRestrictedNeverRequestAgain() async {
        for authorization in [ReminderAccess.denied, .restricted] {
            let service = MockReminderService()
            service.authorization = authorization
            let (model, presentation) = fixture(reminders: service)
            defer { presentation.reset(); model.reminder.endSession() }
            for _ in 0..<2 { await model.reminder.prepare() }
            await model.reminder.refreshAccess(request: true)
            model.reminder.draft.title = "buy milk"
            XCTAssertFalse(model.reminder.canSaveReminder)
            XCTAssertEqual(service.requestCount, 0)
        }
    }

    func testAccessAndListChangesEnableAddWithoutReopening() async {
        let service = MockReminderService()
        service.authorization = .denied
        let (model, presentation) = fixture(reminders: service)
        defer { presentation.reset(); model.reminder.endSession() }
        await model.reminder.prepare()
        model.reminder.draft.title = "test friday 1:00pm"
        XCTAssertEqual(model.reminder.disableReason, "permission")
        service.authorization = .allowed
        service.notifyChanges()
        for _ in 0..<100 where !model.reminder.canSaveReminder { await Task.yield() }
        XCTAssertTrue(model.reminder.canSaveReminder)
        XCTAssertEqual(service.requestCount, 0)
        model.store.reminderListID = "missing"
        service.availableLists = []
        service.notifyChanges()
        for _ in 0..<100 where !model.reminder.lists.isEmpty { await Task.yield() }
        XCTAssertEqual(model.reminder.disableReason, "noWritableList")
        service.availableLists = [ReminderList(id: "default", title: "Default"), ReminderList(id: "other", title: "Other")]
        service.notifyChanges()
        for _ in 0..<100 where !model.reminder.canSaveReminder { await Task.yield() }
        XCTAssertTrue(model.reminder.canSaveReminder)
        XCTAssertEqual(model.reminder.selectedList?.id, "default")
        model.store.reminderListID = "other"
        XCTAssertEqual(model.reminder.selectedList?.id, "other")
        service.authorization = .denied
        service.notifyChanges()
        for _ in 0..<100 where model.reminder.access == .allowed { await Task.yield() }
        XCTAssertFalse(model.reminder.canSaveReminder)
        let saved7 = await model.reminder.saveCurrent()
        XCTAssertFalse(saved7)
        XCTAssertTrue(service.saved.isEmpty)
    }

    func testFailedSaveReenablesAddAndInvalidDateIsRejected() async {
        let service = MockReminderService()
        let (model, presentation) = fixture(reminders: service)
        defer { presentation.reset(); model.reminder.endSession() }
        await model.reminder.prepare()
        model.reminder.draft.title = "buy milk"
        model.reminder.draft.date = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertEqual(model.reminder.disableReason, "invalidDate")
        model.reminder.draft.date = date
        service.failure = .noWritableList
        let failed = await model.reminder.saveCurrent()
        XCTAssertFalse(failed)
        XCTAssertTrue(model.reminder.canSaveReminder)
        XCTAssertEqual(model.reminder.draft.title, "buy milk")
        XCTAssertNotNil(model.reminder.error)
        service.failure = nil
        let saved = await model.reminder.saveCurrent()
        XCTAssertTrue(saved)
        XCTAssertEqual(service.saved.count, 1)
        XCTAssertNil(model.reminder.error)
        XCTAssertFalse(model.reminder.canSaveReminder)
    }

    func testPendingSaveBlocksDuplicateSubmission() async {
        let clock = PausedReminderClock(date: date)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let service = MockReminderService()
        let reminder = QuickReminderModel(service: service, workspace: Stage11Workspace(),
            store: QuickActionStore(preferences: preferences), notifications: presentation.notificationCoordinator, clock: clock)
        defer { reminder.endSession(); presentation.reset() }
        await reminder.prepare()
        reminder.draft.title = "buy milk"
        await clock.pause()
        let first = Task { await reminder.saveCurrent() }
        for _ in 0..<100 where !reminder.isBusy { await Task.yield() }
        XCTAssertTrue(reminder.isBusy)
        XCTAssertEqual(reminder.disableReason, "saveInProgress")
        let duplicate = await reminder.saveCurrent()
        XCTAssertFalse(duplicate)
        await clock.resume()
        let saved = await first.value
        XCTAssertTrue(saved)
        XCTAssertEqual(service.saved.count, 1)
        XCTAssertFalse(reminder.isBusy)
    }

    private func fixture(reminders: MockReminderService = MockReminderService(), workspace: Stage11Workspace = Stage11Workspace()) -> (QuickActionsModel, DynamicIslandPresentationModel) {
        let clock = TestAppClock(now: date, automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let store = QuickActionStore(preferences: preferences)
        let runner = QuickActionRunner(store: store, workspace: workspace, shortcuts: MockShortcutService(),
            notifications: presentation.notificationCoordinator, clock: clock)
        let reminder = QuickReminderModel(service: reminders, workspace: workspace, store: store,
            notifications: presentation.notificationCoordinator, clock: clock)
        return (QuickActionsModel(store: store, runner: runner, reminder: reminder), presentation)
    }
}

@MainActor private final class Stage11Workspace: QuickActionWorkspace {
    var opened: [QuickAction] = []
    var fail = false
    func chooseTarget(for kind: QuickActionKind) async throws -> QuickAction? { nil }
    func resolve(_ action: QuickAction) throws -> QuickAction {
        if fail { throw QuickActionFailure.unavailable }
        return action
    }
    func open(_ action: QuickAction) async throws { if fail { throw QuickActionFailure.unavailable }; opened.append(action) }
    func icon(for action: QuickAction) -> NSImage? { nil }
    func openReminderPrivacy() {}
}

private actor PausedReminderClock: AppClock {
    let date: Date
    private var paused = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(date: Date) { self.date = date }
    func pause() { paused = true }
    func resume() { paused = false; continuation?.resume(); continuation = nil }
    func now() async -> Date {
        if paused { await withCheckedContinuation { continuation = $0 } }
        return date
    }
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}
