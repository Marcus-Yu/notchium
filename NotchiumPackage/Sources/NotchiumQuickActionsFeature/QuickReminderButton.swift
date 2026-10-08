import NotchiumDesignSystem
import AppKit
import SwiftUI
import NotchiumDynamicIsland

struct QuickReminderButton: View {
    let model: QuickReminderModel
    @State private var presented = false
    @State private var isHovered = false
    @NotchReducedMotion private var reduceMotion
    @Environment(\.notchAuxiliaryInteraction) private var interaction

    var body: some View {
        Button {
            interaction.begin()
            presented = true
        } label: {
            NotchUtilityLabel(symbol: "checklist", isHovered: isHovered, isSelected: presented)
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.18), value: isHovered)
        .accessibilityValue(presented ? "Open" : "Closed")
        .help("Quick Reminder")
        .accessibilityLabel("Quick Reminder")
        .accessibilityIdentifier("notchium.shell.quickReminder")
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            QuickReminderComposer(model: model) { presented = false }
        }
        .onChange(of: presented) { _, visible in
            if !visible { interaction.end(actionSelected: false) }
        }
        .onDisappear { if presented { presented = false; interaction.end(actionSelected: false) } }
    }
}

struct QuickReminderComposer: View {
    @Bindable var model: QuickReminderModel
    let close: () -> Void
    @FocusState private var titleFocused: Bool
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Reminder…", text: $model.draft.title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .accessibilityLabel("Reminder")
                .accessibilityIdentifier("notchium.reminder.title")
                .onSubmit(add)
            HStack {
                DatePicker("Due date", selection: Binding(get: { model.draft.date }, set: model.setDate), displayedComponents: .date)
                    .labelsHidden().accessibilityLabel("Due date")
                Spacer()
                Toggle("At Time", isOn: Binding(get: { model.draft.includesTime }, set: { enabled in
                    let revision = model.setIncludesTime(enabled)
                    if enabled { Task { await model.initializeManualTime(revision: revision) } }
                })).toggleStyle(.checkbox)
            }
            if model.draft.includesTime {
                DatePicker("Time", selection: Binding(get: { model.draft.date }, set: model.setDate), displayedComponents: .hourAndMinute)
            }
            if model.access == .denied {
                Text("Reminders access is disabled.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open System Settings", action: model.openPrivacy)
            } else if model.access == .restricted {
                Text("Reminders access is restricted on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if model.access == .allowed && model.lists.isEmpty {
                Text("Create a writable list in Reminders, then try again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSaveReminder)
                    .accessibilityIdentifier("notchium.reminder.add")
            }
        }
        .foregroundStyle(Color.primary)
        .tint(.accentColor)
        .padding(16)
        .frame(width: 320)
        .background(PopoverKeyFocus())
        .task { titleFocused = true; await model.prepare(); titleFocused = true }
        .task(id: model.draft.title) { await model.parseAfterDebounce() }
        .onChange(of: model.canSaveReminder) { _, _ in model.logValidation() }
        .onDisappear { saveTask?.cancel(); model.endSession() }
        .onExitCommand { saveTask?.cancel(); model.cancel(); close() }
    }
    private func add() {
        guard model.canSaveReminder, saveTask == nil else { return }
        saveTask = Task {
            defer { saveTask = nil }
            guard !Task.isCancelled else { return }
            if await model.saveCurrent() { close() }
        }
    }
}

/// The host notch remains nonactivating. Only the native child popover takes text focus.
private struct PopoverKeyFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusView { FocusView() }
    func updateNSView(_ view: FocusView, context: Context) {}
    final class FocusView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.makeKey()
        }
    }
}
