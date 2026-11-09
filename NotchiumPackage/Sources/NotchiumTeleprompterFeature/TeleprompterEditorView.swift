import NotchiumCore
import SwiftUI
import UniformTypeIdentifiers

/// Preparation stays in a native document-sized window; the notch remains a compact reader.
@MainActor
public struct TeleprompterEditorView: View {
    @Bindable private var model: TeleprompterModel
    @State private var importing = false
    @State private var importError: String?
    @State private var pendingAction: DraftAction?
    @State private var showDiscardConfirmation = false
    @State private var deletionID: UUID?
    @State private var showDeleteConfirmation = false
    @State private var showingReadingOptions = false

    private enum DraftAction {
        case new, edit(UUID), importFile
    }

    public init(model: TeleprompterModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            GeometryReader { geometry in
                ScrollView {
                    editor(viewportHeight: geometry.size.height)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(model.editingScriptID == nil ? "New Script" : "Edit Script")
                    .font(.headline)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                editorActions
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.documentTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { model.importDocument(url) }
            case let .failure(error):
                if (error as? CocoaError)?.code != .userCancelled {
                    importError = "The document picker could not open this file. Try again."
                }
            }
        }
        .alert("Discard unsaved changes?", isPresented: $showDiscardConfirmation) {
            Button("Discard Changes", role: .destructive) {
                if let action = pendingAction { perform(action) }
                pendingAction = nil
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text("Save this script before switching if you want to keep your changes.")
        }
        .confirmationDialog("Delete this script?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Script", role: .destructive) {
                if let id = deletionID { model.deleteScript(id) }
                deletionID = nil
            }
            Button("Cancel", role: .cancel) { deletionID = nil }
        } message: {
            Text("The saved copy will be removed from Notchium. The original document stays in place.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scripts").font(.headline)
                Spacer()
                Button("New Script", systemImage: "plus") { request(.new) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New Script")
                    .disabled(editingDisabled)
                    .accessibilityIdentifier("notchium.teleprompter.new")
            }
            .padding(14)
            Divider()
            List(selection: Binding(get: { model.editingScriptID }, set: { id in
                if let id, id != model.editingScriptID { request(.edit(id)) }
            })) {
                ForEach(model.scripts) { script in
                    Label {
                        Text(verbatim: script.title.isEmpty ? "Untitled Script" : script.title)
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: "doc.text")
                    }
                    .tag(script.id)
                    .contextMenu {
                        Button("Delete Script", role: .destructive) { requestDeletion(script.id) }
                            .disabled(editingDisabled)
                    }
                }
            }
            .listStyle(.sidebar)
            .disabled(editingDisabled)
            .overlay {
                if model.libraryLoaded && model.scripts.isEmpty {
                    Text("Save a script to keep it here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(20)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Saved scripts")
            Divider()
            Button("Import Document…", systemImage: "square.and.arrow.down") { request(.importFile) }
                .keyboardShortcut("o", modifiers: .command)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .disabled(editingDisabled)
                .accessibilityIdentifier("notchium.teleprompter.import")
        }
    }

    /// Document actions belong to the native window chrome, outside both scroll views.
    @ViewBuilder private var editorActions: some View {
        if model.isBusy {
            ProgressView().controlSize(.small).accessibilityLabel("Updating scripts")
        }
        if let id = model.editingScriptID {
            Button("Delete", systemImage: "trash", role: .destructive) { requestDeletion(id) }
                .labelStyle(.iconOnly)
                .help("Delete Script")
                .disabled(editingDisabled)
        }
        Button("Open Reader", action: model.showReader)
            .disabled(editingDisabled || model.selectedScriptID == nil || hasUnsavedChanges)
            .accessibilityIdentifier("notchium.teleprompter.openReader")
        Button("Save Script", action: model.saveDraft)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(editingDisabled || model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("notchium.teleprompter.save")
    }

    private func editor(viewportHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.session.isActive {
                HStack(spacing: 10) {
                    Label("Stop reading to edit this script.", systemImage: "pause.circle")
                    Spacer()
                    Button("Stop", action: model.session.stop)
                }
                .font(.callout)
                .padding(10)
                .background(.quaternary, in: .rect(cornerRadius: 8))
            }

            if let error = model.errorMessage ?? importError {
                HStack(alignment: .top, spacing: 10) {
                    Label {
                        Text(verbatim: error).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    Spacer(minLength: 0)
                    if !model.libraryLoaded, model.errorMessage != nil {
                        Button("Retry Library", action: model.start)
                            .disabled(model.isBusy)
                    }
                }
                .font(.callout)
                .foregroundStyle(.red)
                .accessibilityIdentifier("notchium.teleprompter.editorError")
            }

            TextField("Script title", text: $model.draftTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Script title")
                .accessibilityIdentifier("notchium.teleprompter.title")
                .disabled(editingDisabled)

            TextEditor(text: $model.draftText)
                .font(.system(size: 15))
                .lineSpacing(5)
                .padding(6)
                .background(.background, in: .rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 1) }
                .frame(height: max(140, viewportHeight - (showingReadingOptions ? 480 : 340)))
                .accessibilityLabel("Script text")
                .accessibilityHint("Type or paste your script. Imported document text can be edited here.")
                .accessibilityIdentifier("notchium.teleprompter.text")
                .disabled(editingDisabled)

            Text("Import Word, rich text, or text files. Review the extracted text before saving; document layouts and review comments may be omitted.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("Reading Options", isExpanded: $showingReadingOptions) {
                TeleprompterReadingOptions(session: model.session)
                    .padding(.top, 8)
                    .disabled(model.session.isActive)
            }
            .accessibilityIdentifier("notchium.teleprompter.readingOptions")

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Label("Scripts stay on this Mac. Speech following is processed on-device.", systemImage: "lock")
                Text("A speech model may download on first use. Check your sharing preview before a call; the reader may appear in screen captures.")
                Text("Closing this window keeps your draft. Save scripts to keep them after quitting Notchium.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Script editor")
    }

    private var editingDisabled: Bool { model.isBusy || !model.libraryLoaded || model.session.isActive }

    private var hasUnsavedChanges: Bool {
        if let id = model.editingScriptID, let saved = model.scripts.first(where: { $0.id == id }) {
            return model.draftTitle != saved.title || model.draftText != saved.text
        }
        let title = model.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!title.isEmpty && title != "Untitled script")
            || !model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func request(_ action: DraftAction) {
        guard !editingDisabled else { return }
        importError = nil
        if hasUnsavedChanges {
            pendingAction = action
            showDiscardConfirmation = true
        } else { perform(action) }
    }

    private func perform(_ action: DraftAction) {
        switch action {
        case .new: model.newDraft()
        case let .edit(id):
            model.selectScript(id)
            model.beginEditing(id)
        case .importFile: importing = true
        }
    }

    private func requestDeletion(_ id: UUID) {
        deletionID = id
        showDeleteConfirmation = true
    }

    private static let documentTypes: [UTType] = [.plainText, .rtf,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data]
}

@MainActor
private struct TeleprompterReadingOptions: View {
    @Bindable var session: TeleprompterReadingSession

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
            GridRow {
                Text("Reading mode").foregroundStyle(.secondary)
                Picker("Reading mode", selection: $session.mode) {
                    ForEach(TeleprompterMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .labelsHidden()
                .accessibilityIdentifier("notchium.teleprompter.mode")
            }
            GridRow {
                Text("Microphone").foregroundStyle(.secondary)
                HStack {
                    TeleprompterMicrophonePicker(session: session).labelsHidden()
                    Button("Refresh Microphones", systemImage: "arrow.clockwise", action: session.refreshInputDevices)
                        .labelStyle(.iconOnly).help("Refresh Microphones")
                }
                .disabled(!session.mode.usesMicrophone)
            }
            GridRow {
                Text("Language").foregroundStyle(.secondary)
                Picker("Speech language", selection: $session.localeIdentifier) {
                    Text("English (United States)").tag("en-US")
                    Text("English (United Kingdom)").tag("en-GB")
                    Text("French").tag("fr-FR")
                    Text("German").tag("de-DE")
                    Text("Spanish").tag("es-ES")
                }
                .labelsHidden()
                .disabled(!session.mode.usesMicrophone)
                .accessibilityIdentifier("notchium.teleprompter.language")
            }
            GridRow {
                Text("Fixed pace").foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Slider(value: $session.wordsPerMinute, in: 50...300, step: 5)
                        .accessibilityLabel("Fixed reading pace")
                        .accessibilityValue("\(Int(session.wordsPerMinute)) words per minute")
                    Text("\(Int(session.wordsPerMinute)) wpm").monospacedDigit().frame(width: 65, alignment: .trailing)
                }
                .disabled(session.mode == .voiceFollow)
            }
            GridRow {
                Text("Reader text").foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Slider(value: $session.fontSize, in: TeleprompterReaderStyle.fontRange, step: 1)
                        .accessibilityLabel("Reader text size")
                        .accessibilityValue("\(Int(session.fontSize)) points")
                    Text("\(Int(session.fontSize)) pt").monospacedDigit().frame(width: 65, alignment: .trailing)
                }
            }
        }
        .font(.callout)
    }
}
