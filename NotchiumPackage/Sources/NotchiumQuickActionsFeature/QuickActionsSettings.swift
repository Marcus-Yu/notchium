import SwiftUI
import AppKit
import NotchiumCore

public struct QuickActionsSettings: View {
    public let model: QuickActionsModel
    @State private var editing: QuickAction?
    @State private var selection: UUID?
    @State private var error: String?
    public init(model: QuickActionsModel) { self.model = model }

    public var body: some View {
        Section("Shortcuts & Actions") {
            List(selection: $selection) {
                ForEach(model.store.actions) { action in
                    actionRow(action).tag(action.id)
                        .contextMenu {
                            Button("Run") { model.runner.run(action) }.disabled(!action.enabled)
                            if model.runner.running.contains(action.id) {
                                Button("Cancel Run") { model.runner.cancel(action.id) }
                            }
                            Button("Edit…") { editing = action }
                            Button(action.pinnedToHome ? "Unpin from Home" : "Pin to Home") { togglePin(action) }
                            Button("Remove", role: .destructive) { perform { try model.store.remove(action.id) } }
                        }
                }
                .onMove { source, destination in perform { try model.store.move(from: source, to: destination) } }
            }
            .frame(minHeight: 130, idealHeight: 170)
            .overlay {
                if model.store.actions.isEmpty {
                    Text("Add an existing shortcut, app, file, folder, or website.")
                        .font(.callout).foregroundStyle(.secondary).padding()
                }
            }
            HStack {
                Button("Add…", systemImage: "plus") { editing = QuickAction(kind: .shortcut) }
                Button("Remove", systemImage: "minus") {
                    if let selection { perform { try model.store.remove(selection) } }
                }.disabled(selection == nil)
                Button("Edit…") {
                    editing = model.store.actions.first { $0.id == selection }
                }.disabled(selection == nil)
                Spacer()
                Button("Refresh") { Task { await model.runner.refresh() } }.disabled(model.runner.refreshing)
            }
            if let message = error ?? model.store.error ?? model.runner.discoveryError {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .sheet(item: $editing) { action in
            QuickActionEditor(action: action, model: model)
        }
        .task { consumeEditRequest(); await model.runner.refresh(); await model.reminder.refreshAccess() }
        .onChange(of: model.requestedEditID) { _, _ in consumeEditRequest() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.runner.refresh(); await model.reminder.refreshAccess() }
        }
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
                    Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                } else { Text(action.kind.title).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if model.runner.showingProgress.contains(action.id) { ProgressView().controlSize(.small) }
            if action.pinnedToHome { Image(systemName: "pin.fill").help("Pinned to Home") }
            Toggle("Enabled", isOn: Binding(get: { action.enabled }, set: { value in
                var changed = action; changed.enabled = value; perform { try model.store.save(changed) }
            })).labelsHidden().accessibilityLabel("Enable \(action.displayName)")
        }
        .padding(.vertical, 4)
    }
    private func togglePin(_ action: QuickAction) {
        var changed = action; changed.pinnedToHome.toggle()
        perform { try model.store.save(changed) }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); error = nil } catch { self.error = error.localizedDescription }
    }
}
