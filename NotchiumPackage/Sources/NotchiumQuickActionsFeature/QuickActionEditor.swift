import SwiftUI
import NotchiumCore

struct QuickActionEditor: View {
    @State var action: QuickAction
    let model: QuickActionsModel
    @State private var error: String?
    @State private var choosing = false
    @Environment(\.dismiss) private var dismiss
    private let icons = ["globe", "link", "star", "heart", "bookmark", "bolt", "checklist", "folder", "doc"]
    private var isNew: Bool { !model.store.actions.contains { $0.id == action.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add Action" : "Edit Action").font(.headline)
            Form {
                Picker("Type", selection: $action.kind) {
                    ForEach(QuickActionKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                switch action.kind {
                case .shortcut:
                    Picker("Shortcut", selection: Binding(get: { model.runner.shortcuts.contains(where: { $0.id == action.shortcutID && $0.name == action.target }) ? (action.shortcutID?.uuidString ?? "") : "" }, set: { value in
                        guard let chosen = model.runner.shortcuts.first(where: { $0.id.uuidString == value }) else { return }
                        action.shortcutID = chosen.id; action.target = chosen.name
                        if action.displayName.isEmpty { action.displayName = chosen.name }
                    })) {
                        Text("Select an existing shortcut").tag("")
                        ForEach(model.runner.shortcuts) { Text($0.name).tag($0.id.uuidString) }
                    }
                    Button("Refresh Shortcuts") { Task { await model.runner.refresh() } }
                        .disabled(model.runner.refreshing)
                    if let error = model.runner.discoveryError { Text(error).font(.caption).foregroundStyle(.secondary) }
                case .url:
                    TextField("Website", text: $action.target, prompt: Text("https://example.com"))
                    if !action.target.isEmpty && QuickAction.validatedWebURL(action.target) == nil {
                        Text("Enter a full http or https website address.").font(.caption).foregroundStyle(.secondary)
                    }
                case .application, .file, .folder:
                    HStack {
                        Text(URL(string: action.target)?.lastPathComponent ?? "No item selected")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { choose() }.disabled(choosing)
                    }
                }
                TextField("Name", text: $action.displayName)
                Picker("Icon", selection: Binding(get: { action.symbol ?? "" }, set: { action.symbol = $0.isEmpty ? nil : $0 })) {
                    Text("Automatic").tag("")
                    ForEach(icons, id: \.self) { symbol in Label(symbol.capitalized, systemImage: symbol).tag(symbol) }
                }
                Toggle("Enabled", isOn: $action.enabled)
                Toggle("Pin to Home", isOn: $action.pinnedToHome)
                Text("Home supports up to four pinned actions.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: save).keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }
        .padding(20).frame(width: 420)
        .onChange(of: action.kind) { _, _ in action.target = ""; action.bookmark = nil; action.shortcutID = nil; error = nil }
        .onChange(of: action.target) { _, value in
            if action.displayName.isEmpty && action.kind == .shortcut { action.displayName = value }
        }
        .task { if action.kind == .shortcut { await model.runner.refresh() } }
    }
    private var valid: Bool {
        guard !action.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch action.kind {
        case .url: return QuickAction.validatedWebURL(action.target) != nil
        case .shortcut: return model.runner.shortcuts.filter { $0.id == action.shortcutID && $0.name == action.target }.count == 1
        default: return action.bookmark != nil
        }
    }
    private func choose() {
        choosing = true
        Task {
            defer { choosing = false }
            do {
                if let chosen = try await model.runner.workspace.chooseTarget(for: action.kind) {
                    action.target = chosen.target; action.bookmark = chosen.bookmark
                    if action.displayName.isEmpty { action.displayName = chosen.displayName }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        do {
            action.displayName = action.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            try model.store.save(action)
            model.runner.validate(action)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
