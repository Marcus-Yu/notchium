import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumPersistence
import NotchiumServices
import Observation
import SwiftUI

@MainActor @Observable
public final class TeleprompterModel: NotchTeleprompterRendering {
    public let session: TeleprompterReadingSession
    public let meetingSuggestion: TeleprompterMeetingSuggestion
    public private(set) var scripts: [TeleprompterScript] = []
    public private(set) var selectedScriptID: UUID?
    public private(set) var editingScriptID: UUID?
    public var draftTitle = "Untitled script"
    public var draftText = ""
    public private(set) var errorMessage: String?
    public private(set) var isBusy = false
    public private(set) var libraryLoaded = false
    public var selectedScript: TeleprompterScript? { scripts.first { $0.id == selectedScriptID } }
    public var meetingSuggested: Bool { meetingSuggestion.isSuggested }
    public var isReading: Bool { session.isActive }
    @ObservationIgnored public var openEditor: @MainActor () -> Void = {}
    @ObservationIgnored public var openReader: @MainActor () -> Void = {}
    @ObservationIgnored private let store: any TeleprompterScriptStoring
    @ObservationIgnored private let importer: any TeleprompterDocumentImporting
    @ObservationIgnored private let uuids: any UUIDGenerating
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var mutationTask: Task<Void, Never>?
    @ObservationIgnored private var visibleSources: Set<String> = []

    public init(speech: any TeleprompterSpeechService, store: any TeleprompterScriptStoring,
                importer: any TeleprompterDocumentImporting,
                meetingContext: any TeleprompterMeetingContextService, calendar: any CalendarService,
                activities: ActivityCoordinator, clock: any AppClock, uuids: any UUIDGenerating) {
        self.store = store
        self.importer = importer
        self.uuids = uuids
        session = TeleprompterReadingSession(speech: speech, clock: clock)
        meetingSuggestion = TeleprompterMeetingSuggestion(context: meetingContext, calendar: calendar,
                                                        activities: activities, clock: clock, uuids: uuids)
    }

    public func start() {
        session.refreshInputDevices()
        meetingSuggestion.start()
        guard loadTask == nil, !libraryLoaded else { return }
        loadTask = Task { [weak self, store] in
            do {
                let scripts = try await store.load()
                guard !Task.isCancelled, let self else { return }
                self.scripts = scripts
                self.libraryLoaded = true
                if let first = scripts.first { self.selectScript(first.id); self.beginEditing(first.id) }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.errorMessage = Self.storageMessage(error)
                // Preserve unreadable/newer libraries; no empty automatic overwrite.
            }
            self?.loadTask = nil
        }
    }

    public func stop() {
        session.pause()
        meetingSuggestion.stop()
        visibleSources.removeAll()
        loadTask?.cancel(); loadTask = nil
        mutationTask?.cancel(); mutationTask = nil
        isBusy = false
    }

    public func selectScript(_ id: UUID) {
        guard let script = scripts.first(where: { $0.id == id }) else { return }
        session.prepare(text: script.text)
        selectedScriptID = id
    }

    public func beginEditing(_ id: UUID?) {
        session.pause()
        guard let script = scripts.first(where: { $0.id == id }) else { newDraft(); return }
        editingScriptID = script.id
        draftTitle = script.title
        draftText = script.text
    }

    public func newDraft() {
        session.pause()
        editingScriptID = nil
        draftTitle = "Untitled script"
        draftText = ""
    }

    public func saveDraft() {
        guard libraryLoaded, !isBusy, !session.isActive,
              !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = draftText
        let existingID = editingScriptID
        errorMessage = nil
        isBusy = true
        mutationTask = Task { [weak self, store, uuids] in
            let id = if let existingID { existingID } else { await uuids.next() }
            guard !Task.isCancelled, let self else { return }
            let script = TeleprompterScript(id: id, title: title.isEmpty ? "Untitled script" : title, text: text)
            var saved = self.scripts
            if let index = saved.firstIndex(where: { $0.id == id }) { saved[index] = script }
            else { saved.append(script) }
            do {
                try await store.save(saved)
                guard !Task.isCancelled else { return }
                self.scripts = saved
                self.editingScriptID = id
                self.draftTitle = script.title
                self.selectScript(id)
            } catch { if !Task.isCancelled { self.errorMessage = Self.storageMessage(error) } }
            self.isBusy = false
            self.mutationTask = nil
        }
    }

    public func deleteScript(_ id: UUID) {
        guard libraryLoaded, !isBusy, !session.isActive else { return }
        let saved = scripts.filter { $0.id != id }
        isBusy = true
        errorMessage = nil
        mutationTask = Task { [weak self, store] in
            do {
                try await store.save(saved)
                guard !Task.isCancelled, let self else { return }
                self.scripts = saved
                if self.selectedScriptID == id {
                    self.selectedScriptID = nil
                    self.session.prepare(text: "")
                    if let first = saved.first { self.selectScript(first.id) }
                }
                if self.editingScriptID == id { self.beginEditing(self.selectedScriptID) }
            } catch {
                if !Task.isCancelled { self?.errorMessage = Self.storageMessage(error) }
            }
            self?.isBusy = false
            self?.mutationTask = nil
        }
    }

    public func importDocument(_ url: URL) {
        guard libraryLoaded, !isBusy, !session.isActive else { return }
        isBusy = true
        errorMessage = nil
        mutationTask = Task { [weak self, importer] in
            do {
                let text = try await importer.importDocument(at: url)
                guard !Task.isCancelled, let self else { return }
                self.editingScriptID = nil
                self.draftTitle = url.deletingPathExtension().lastPathComponent
                self.draftText = text
            } catch {
                if !Task.isCancelled {
                    self?.errorMessage = (error as? TeleprompterDocumentFailure)?.localizedDescription
                        ?? "The document couldn’t be imported. Try a TXT, RTF, or Word DOCX file."
                }
            }
            self?.isBusy = false
            self?.mutationTask = nil
        }
    }

    public func editScripts() { session.pause(); openEditor() }
    public func showReader() { guard selectedScript != nil else { return }; session.pause(); openReader() }
    public func clearError() { errorMessage = nil }
    public func expandedTeleprompter(prepareToRead: @escaping @MainActor () -> Void) -> AnyView {
        AnyView(TeleprompterPage(model: self, prepareToRead: prepareToRead))
    }

    public func setReadingVisible(_ visible: Bool, source: String) {
        if visible { visibleSources.insert(source) }
        else { visibleSources.remove(source) }
        if visibleSources.isEmpty { session.pause() }
    }

    private static func storageMessage(_ error: any Error) -> String {
        (error as? TeleprompterScriptStoreFailure)?.localizedDescription ?? "The script library couldn’t be saved or loaded."
    }

    isolated deinit {
        loadTask?.cancel()
        mutationTask?.cancel()
    }
}
