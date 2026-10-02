import SwiftUI
import AppKit
import NotchiumCore

public struct QuickActionsSettings: View {
    public let model: QuickActionsModel
    private let showActions: Bool
    private let showReminders: Bool
    @State private var editing: QuickAction?
    @State private var selection: UUID?
    @State private var error: String?
    public init(model: QuickActionsModel, showActions: Bool = true, showReminders: Bool = true) {
        self.model = model; self.showActions = showActions; self.showReminders = showReminders
    }
    public var body: some View {
        Group {
            if showActions { actionSection }
            if showReminders { reminderSection }
        }
        .sheet(item: $editing) { action in QuickActionEditor(action: action, model: model) }
        .task {
            if showActions { consumeEditRequest(); await model.runner.refresh() }
            if showReminders { await model.reminder.refreshAccess() }
        }
        .onChange(of: model.requestedEditID) { _, _ in if showActions { consumeEditRequest() } }
    }
    private var actionSection: some View {
        Section("Shortcuts") {
            List(selection: $selection) {
                ForEach(model.store.actions) { action in
                    actionRow(action).tag(action.id)
                        .contextMenu {
                            Button("Run") { model.runner.run(action) }.disabled(!model.runner.canRun(action))
                            Button("Check Availability") { Task { await model.runner.validate(action) } }
                            if model.runner.running.contains(action.id) { Button("Cancel Run") { model.runner.cancel(action.id) } }
                            Button("Edit…") { editing = action }
                            Button(action.pinnedToHome ? "Hide from Home" : "Show on Home") { togglePin(action) }
                            Button("Remove", role: .destructive) { perform { try model.store.remove(action.id) } }
                        }
                }
                .onMove { source, destination in perform { try model.store.move(from: source, to: destination) } }
            }
            .frame(height: 175)
            .overlay {
                if model.store.actions.isEmpty {
                    Text("Add an app, file, folder, URL, Apple Shortcut, or system action.")
                        .font(.callout).foregroundStyle(.secondary).padding()
                }
            }
            HStack {
                Button("Add Shortcut…", systemImage: "plus") {
                    editing = QuickAction(kind: .application, pinnedToHome: true)
                }
                Button("Remove", systemImage: "minus") {
                    if let selection { perform { try model.store.remove(selection) }; self.selection = nil }
                }.disabled(selectedAction == nil)
                Button("Edit…") { editing = selectedAction }.disabled(selectedAction == nil)
                Button { moveSelection(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!canMoveSelection(-1)).help("Move shortcut up").accessibilityLabel("Move shortcut up")
                Button { moveSelection(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!canMoveSelection(1)).help("Move shortcut down").accessibilityLabel("Move shortcut down")
                Spacer()
                Button { Task { await model.runner.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.runner.refreshing).help("Refresh availability").accessibilityLabel("Refresh shortcut availability")
            }
            Text("Drag to reorder, or select a shortcut and use the arrows.").font(.caption).foregroundStyle(.secondary)
            if let message = error ?? model.store.error ?? model.runner.discoveryError {
                Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var reminderSection: some View {
        Section("Reminders") {
            if model.reminder.access == .allowed {
                Picker("Default Reminder List", selection: Binding(
                    get: { model.store.reminderListID }, set: { model.store.reminderListID = $0 })) {
                    Text("System Default").tag("")
                    ForEach(model.reminder.lists) { Text($0.title).tag($0.id) }
                }
                Text("Scheduled reminders can appear in Calendar when Scheduled Reminders is enabled there.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Enable Quick Reminder…") { Task { await model.reminder.refreshAccess(request: true) } }
                if model.reminder.access == .denied || model.reminder.access == .restricted {
                    Button("Open Reminders Privacy Settings", action: model.reminder.openPrivacy)
                }
            }
            if let error = model.reminder.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
    private var selectedAction: QuickAction? { model.store.actions.first { $0.id == selection } }
    private func canMoveSelection(_ delta: Int) -> Bool {
        guard let index = model.store.actions.firstIndex(where: { $0.id == selection }) else { return false }
        return model.store.actions.indices.contains(index + delta)
    }
    private func moveSelection(_ delta: Int) {
        guard canMoveSelection(delta), let index = model.store.actions.firstIndex(where: { $0.id == selection }) else { return }
        perform { try model.store.move(from: IndexSet(integer: index), to: delta < 0 ? index - 1 : index + 2) }
    }
    private func consumeEditRequest() {
        guard let id = model.requestedEditID else { return }
        editing = model.store.actions.first { $0.id == id }
        model.requestedEditID = nil
    }
    private func actionRow(_ action: QuickAction) -> some View {
        HStack(spacing: 10) {
            QuickActionIcon(action: action, runner: model.runner)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName).lineLimit(1)
                if let issue = model.runner.unavailable[action.id] {
                    Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else { Text(action.kind.title).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if model.runner.showingProgress.contains(action.id) { ProgressView().controlSize(.small) }
            if action.pinnedToHome { Image(systemName: "pin.fill").help("Shown on Home") }
            Toggle("Enabled", isOn: Binding(get: { action.enabled }, set: { value in
                var changed = action; changed.enabled = value; perform { try model.store.save(changed) }
            })).labelsHidden().accessibilityLabel("Enable \(action.displayName)")
        }
        .padding(.vertical, 4)
        .accessibilityActions {
            Button("Move up") {
                selection = action.id; moveSelection(-1)
            }
            Button("Move down") {
                selection = action.id; moveSelection(1)
            }
        }
    }
    private func togglePin(_ action: QuickAction) {
        var changed = action; changed.pinnedToHome.toggle()
        perform { try model.store.save(changed) }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); error = nil } catch { self.error = error.localizedDescription }
    }
}
