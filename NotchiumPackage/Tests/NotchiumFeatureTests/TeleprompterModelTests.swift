import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumPersistence
import NotchiumServices
@testable import NotchiumTeleprompterFeature
import XCTest

@MainActor
final class TeleprompterModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let scriptID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A0")!

    func testLibraryLoadsWithoutListeningAndSaveUpdatesOneScriptThenDeletionSelectsRemaining() async {
        let original = script()
        let other = TeleprompterScript(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
                                      title: "Second", text: "Another saved script for a meeting.")
        let store = MockTeleprompterScriptStore(scripts: [original, other])
        let speech = MockTeleprompterSpeechService()
        let model = makeModel(store: store, speech: speech)
        defer { model.stop() }
        model.start()
        await eventually { model.libraryLoaded }
        XCTAssertEqual(model.selectedScriptID, original.id)
        XCTAssertEqual(model.draftText, original.text)
        let startsAfterLoading = await speech.startCount
        XCTAssertEqual(startsAfterLoading, 0)

        model.draftTitle = "Edited title"
        model.draftText = "An edited version of the selected script."
        model.saveDraft()
        await eventually { !model.isBusy }
        XCTAssertEqual(model.scripts.count, 2)
        XCTAssertEqual(model.scripts.first?.id, original.id)
        XCTAssertEqual(model.scripts.first?.title, "Edited title")
        XCTAssertEqual(model.session.alignment.text, model.draftText)
        let saved = await store.scripts
        XCTAssertEqual(saved, model.scripts)

        model.deleteScript(original.id)
        await eventually { !model.isBusy }
        XCTAssertEqual(model.scripts, [other])
        XCTAssertEqual(model.selectedScriptID, other.id)
        XCTAssertEqual(model.editingScriptID, other.id)
        XCTAssertEqual(model.session.alignment.text, other.text)
        let persistedAfterDeletion = await store.scripts
        XCTAssertEqual(persistedAfterDeletion, [other])
    }

    func testNewDraftCreatesAStableScriptAndSelectsItsSavedSnapshot() async {
        let store = MockTeleprompterScriptStore()
        let model = makeModel(store: store)
        defer { model.stop() }
        model.start()
        await eventually { model.libraryLoaded }
        model.newDraft()
        model.draftTitle = "  Presentation  "
        model.draftText = "Welcome to this presentation. Here is our plan."
        model.saveDraft()
        await eventually { !model.isBusy }
        let first = model.scripts.first
        XCTAssertEqual(model.scripts.count, 1)
        XCTAssertEqual(first?.title, "Presentation")
        XCTAssertEqual(first?.id, model.selectedScriptID)
        XCTAssertEqual(first?.id, model.editingScriptID)
        XCTAssertEqual(first?.text, model.session.alignment.text)
        model.draftText += " Thank you."
        model.saveDraft()
        await eventually { !model.isBusy }
        XCTAssertEqual(model.scripts.count, 1)
        XCTAssertEqual(model.scripts.first?.id, first?.id)
    }

    func testImportEditsDraftWithoutChangingSavedOrReadingSnapshot() async {
        let original = script()
        let store = MockTeleprompterScriptStore(scripts: [original])
        let imported = "Text extracted from a different Word document."
        let speech = MockTeleprompterSpeechService()
        let model = makeModel(store: store, speech: speech,
                              importer: MockTeleprompterDocumentService(result: .success(imported)))
        defer { model.stop() }
        model.start()
        await eventually { model.libraryLoaded }
        model.session.mode = .fixedSpeed
        model.session.start()
        model.importDocument(URL(fileURLWithPath: "/fixture/new-script.docx"))
        XCTAssertTrue(model.session.isActive)
        XCTAssertEqual(model.draftText, original.text, "An active script cannot be replaced by import")

        model.session.pause()
        model.importDocument(URL(fileURLWithPath: "/fixture/new-script.docx"))
        await eventually { !model.isBusy }
        XCTAssertEqual(model.draftText, imported)
        XCTAssertEqual(model.draftTitle, "new-script")
        XCTAssertNil(model.editingScriptID)
        XCTAssertEqual(model.scripts, [original])
        XCTAssertEqual(model.selectedScriptID, original.id)
        XCTAssertEqual(model.session.alignment.text, original.text)
        let persisted = await store.scripts
        let starts = await speech.startCount
        XCTAssertEqual(persisted, [original])
        XCTAssertEqual(starts, 0, "Fixed pace and document preparation never open a microphone")
    }

    func testFailedLibraryLoadCannotOverwriteItsOriginalContents() async {
        let original = script()
        let store = LoadFailureRecordingStore(scripts: [original])
        let model = makeModel(store: store)
        defer { model.stop() }
        model.start()
        await eventually { model.errorMessage != nil }
        XCTAssertFalse(model.libraryLoaded)
        model.draftText = "A new draft must not overwrite an unreadable library."
        model.saveDraft()
        await drainTasks()
        let saves = await store.saveCount
        let preserved = await store.scripts
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(preserved, [original])
    }

    func testReadingPausesOnlyAfterTheLastDisplayHides() async {
        let speech = MockTeleprompterSpeechService()
        let model = makeModel(store: MockTeleprompterScriptStore(scripts: [script()]), speech: speech)
        defer { model.stop() }
        model.start()
        await eventually { model.libraryLoaded }
        model.setReadingVisible(true, source: "display.one")
        model.setReadingVisible(true, source: "display.two")
        model.session.start()
        await eventually { model.session.state == .waiting }
        let stopsBeforeHiding = await speech.stopCount
        model.setReadingVisible(false, source: "display.one")
        XCTAssertTrue(model.session.isActive)
        model.setReadingVisible(false, source: "display.one")
        XCTAssertTrue(model.session.isActive, "Duplicate hide from one display must not close the other")
        model.setReadingVisible(false, source: "display.two")
        XCTAssertEqual(model.session.state, .paused)
        await eventually { await speech.stopCount > stopsBeforeHiding }
    }

    func testNativeCallSuggestsTeleprompterWithoutCalendarAndDismissesOnStop() async {
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let suggestion = TeleprompterMeetingSuggestion(
            context: MockTeleprompterMeetingContextService(context: .probableCall(provider: "Zoom")),
            calendar: MockCalendarService(), activities: activities, clock: clock, uuids: uuids())
        suggestion.start()
        await eventually { suggestion.isSuggested && !activities.liveActivities.isEmpty }
        XCTAssertEqual(activities.liveActivities.count, 1)
        XCTAssertEqual(activities.liveActivities.first?.destination, .teleprompter)
        XCTAssertEqual(activities.liveActivities.first?.presentationStyle, NotchActivityPresentationStyle.none)
        suggestion.stop()
        XCTAssertFalse(suggestion.isSuggested)
        XCTAssertTrue(activities.liveActivities.isEmpty)
    }

    func testCalendarMeetingAloneDoesNotKeepASuggestionAlive() async {
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let context = PushMeetingContext(initial: .probableCall(provider: "Zoom"))
        let activities = ActivityCoordinator(clock: clock)
        let suggestion = TeleprompterMeetingSuggestion(context: context,
            calendar: MockCalendarService(snapshot: .init(availability: .available, upcomingEvents: [event()])),
            activities: activities, clock: clock, uuids: uuids())
        defer { suggestion.stop() }
        suggestion.start()
        await eventually { suggestion.isSuggested }
        await context.emit(.idle)
        await eventually { !suggestion.isSuggested }
        XCTAssertTrue(activities.liveActivities.isEmpty)
    }

    func testBrowserInputAndACurrentVideoMeetingTogetherSuggestReader() async {
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        let suggestion = TeleprompterMeetingSuggestion(
            context: MockTeleprompterMeetingContextService(context: .browserUsingInput),
            calendar: MockCalendarService(snapshot: .init(availability: .available, upcomingEvents: [event()])),
            activities: activities, clock: clock, uuids: uuids())
        defer { suggestion.stop() }
        suggestion.start()
        await eventually { suggestion.isSuggested }
        XCTAssertTrue(suggestion.isSuggested)
    }

    func testBrowserInputDoesNotTreatExpiredAllDayLinklessOrFutureEventsAsACall() async {
        let invalidEvents = [
            event(start: -600, end: 0),
            event(allDay: true),
            event(hasURL: false),
            event(start: 60, end: 600)
        ]
        for event in invalidEvents {
            let clock = TestAppClock(now: now, automaticallyAdvances: false)
            let activities = ActivityCoordinator(clock: clock)
            let context = PushMeetingContext(initial: .probableCall(provider: "Zoom"))
            let suggestion = TeleprompterMeetingSuggestion(context: context,
                calendar: MockCalendarService(snapshot: .init(availability: .available, upcomingEvents: [event])),
                activities: activities, clock: clock, uuids: uuids())
            suggestion.start()
            await eventually { suggestion.isSuggested }
            await context.emit(.browserUsingInput)
            await eventually { !suggestion.isSuggested }
            XCTAssertTrue(activities.liveActivities.isEmpty)
            suggestion.stop()
        }
    }

    private func script() -> TeleprompterScript {
        TeleprompterScript(id: scriptID, title: "Opening", text: "Welcome everyone to the meeting. Here is our agenda.")
    }

    private func makeModel(store: any TeleprompterScriptStoring = MockTeleprompterScriptStore(),
                           speech: MockTeleprompterSpeechService = MockTeleprompterSpeechService(),
                           importer: any TeleprompterDocumentImporting = MockTeleprompterDocumentService()) -> TeleprompterModel {
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        return TeleprompterModel(speech: speech, store: store, importer: importer,
            meetingContext: MockTeleprompterMeetingContextService(), calendar: MockCalendarService(),
            activities: ActivityCoordinator(clock: clock), clock: clock, uuids: uuids())
    }

    private func event(start: TimeInterval = -60, end: TimeInterval = 600,
                       allDay: Bool = false, hasURL: Bool = true) -> CalendarEventSummary {
        CalendarEventSummary(id: scriptID, title: "Meeting", startDate: now.addingTimeInterval(start),
            endDate: now.addingTimeInterval(end),
            meetingURL: hasURL ? URL(string: "https://meet.google.com/abc-defg-hij") : nil, isAllDay: allDay)
    }

    private func uuids() -> SequenceUUIDGenerator {
        SequenceUUIDGenerator(values: (1...32).map {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", $0))!
        })
    }

    private func eventually(_ condition: @MainActor () async -> Bool,
                             file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Expected asynchronous state was not reached", file: file, line: line)
    }

    private func drainTasks() async {
        for _ in 0..<50 { await Task.yield() }
    }
}

private actor LoadFailureRecordingStore: TeleprompterScriptStoring {
    private(set) var scripts: [TeleprompterScript]
    private(set) var saveCount = 0
    init(scripts: [TeleprompterScript]) { self.scripts = scripts }
    func load() throws -> [TeleprompterScript] { throw TeleprompterScriptStoreFailure.unreadable }
    func save(_ scripts: [TeleprompterScript]) { saveCount += 1; self.scripts = scripts }
}

private actor PushMeetingContext: TeleprompterMeetingContextService {
    private let initial: TeleprompterMeetingContext
    private var continuation: AsyncStream<TeleprompterMeetingContext>.Continuation?
    init(initial: TeleprompterMeetingContext) { self.initial = initial }
    func updates() -> AsyncStream<TeleprompterMeetingContext> {
        let pair = AsyncStream.makeStream(of: TeleprompterMeetingContext.self)
        continuation = pair.continuation
        pair.continuation.yield(initial)
        return pair.stream
    }
    func emit(_ value: TeleprompterMeetingContext) { continuation?.yield(value) }
}
