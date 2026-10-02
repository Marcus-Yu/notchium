import SwiftUI
import NotchiumCore

struct QuickActionEditor: View {
    @State private var action: QuickAction
    let model: QuickActionsModel
    @State private var error: String?
    @State private var choosing = false
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    private let icons = ["globe", "link", "star", "heart", "bookmark", "bolt", "checklist", "folder", "doc"]
    private var isNew: Bool { !model.store.actions.contains { $0.id == action.id } }

    init(action: QuickAction, model: QuickActionsModel) {
        _action = State(initialValue: action)
        self.model = model
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add Shortcut" : "Edit Shortcut").font(.headline)
            Form {
                Picker("Action", selection: $action.kind) {
                    ForEach(QuickActionKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }.disabled(!isNew || choosing || saving)
                targetEditor
                TextField("Name", text: $action.displayName).focused($nameFocused)
                Picker("Icon", selection: Binding(get: { action.symbol ?? "" }, set: { action.symbol = $0.isEmpty ? nil : $0 })) {
                    Text("Automatic").tag("")
                    ForEach(icons, id: \.self) { symbol in Label(symbol.capitalized, systemImage: symbol).tag(symbol) }
                }
                Toggle("Enabled", isOn: $action.enabled)
                Toggle("Show on Home", isOn: $action.pinnedToHome)
                Text("Shortcuts stay inside Home’s fixed size. Enable the Shortcuts section in Customize Home.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction).disabled(!valid || choosing || saving)
            }
        }
        .padding(20).frame(width: 420)
        .accessibilityIdentifier("notchium.shortcut.editor")
        .onChange(of: action.kind) { _, kind in
            action.target = ""; action.bookmark = nil; action.shortcutID = nil; action.bundleIdentifier = nil
            action.displayName = ""; action.symbol = nil; error = nil
            if kind == .systemAction { chooseSystemAction(.systemSettings) }
        }
        .task(id: action.kind) { if action.kind == .shortcut { await model.runner.refresh(force: false) } }
    }
    @ViewBuilder private var targetEditor: some View {
        switch action.kind {
        case .shortcut:
            Picker("Shortcut", selection: Binding(get: {
                model.runner.shortcuts.contains(where: { $0.id == action.shortcutID && $0.name == action.target })
                    ? (action.shortcutID?.uuidString ?? "") : ""
            }, set: { value in
                guard let chosen = model.runner.shortcuts.first(where: { $0.id.uuidString == value }) else { return }
                action.shortcutID = chosen.id; action.target = chosen.name
                if action.displayName.isEmpty { action.displayName = chosen.name }
            })) {
                Text("Select an existing shortcut").tag("")
                ForEach(model.runner.shortcuts) { Text($0.name).tag($0.id.uuidString) }
            }
            Button("Refresh Shortcuts") { Task { await model.runner.refresh() } }.disabled(model.runner.refreshing)
            if let error = model.runner.discoveryError {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
            }
        case .url:
            TextField("URL", text: $action.target, prompt: Text("https://example.com or an app link"))
            if !action.target.isEmpty && QuickAction.validatedURL(action.target) == nil {
                Text("Enter a full web address or a valid app link.").font(.caption).foregroundStyle(.secondary)
            }
        case .application, .file, .folder:
            HStack {
                Text(URL(string: action.target)?.lastPathComponent ?? "No item selected")
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { choose() }.disabled(choosing || saving)
            }
            if let issue = model.runner.unavailable[action.id] {
                Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
            }
        case .systemAction:
            Picker("System Action", selection: Binding(get: {
                NativeHomeAction(rawValue: action.target) ?? .systemSettings
            }, set: chooseSystemAction)) {
                ForEach(NativeHomeAction.allCases) { Text($0.title).tag($0) }
            }
        }
    }
    private var valid: Bool {
        guard !action.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch action.kind {
        case .url: return QuickAction.validatedURL(action.target) != nil
        case .shortcut: return model.runner.shortcuts.filter { $0.id == action.shortcutID && $0.name == action.target }.count == 1
        case .systemAction: return NativeHomeAction(rawValue: action.target) != nil
        default: return action.bookmark != nil || (action.kind == .application && action.bundleIdentifier != nil)
        }
    }
    private func chooseSystemAction(_ native: NativeHomeAction) {
        let previousTitle = NativeHomeAction(rawValue: action.target)?.title
        action.target = native.rawValue
        if action.displayName.isEmpty || action.displayName == previousTitle { action.displayName = native.title }
    }
    private func choose() {
        choosing = true
        Task {
            defer { choosing = false }
            do {
                if let chosen = try await model.runner.workspace.chooseTarget(for: action.kind) {
                    action.target = chosen.target; action.bookmark = chosen.bookmark; action.bundleIdentifier = chosen.bundleIdentifier
                    if action.displayName.isEmpty { action.displayName = chosen.displayName }
                    nameFocused = true
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func save() async {
        saving = true
        defer { saving = false }
        do {
            action.displayName = action.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if action.kind == .url { action.target = action.target.trimmingCharacters(in: .whitespacesAndNewlines) }
            try model.store.save(action)
            await model.runner.validate(action)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
