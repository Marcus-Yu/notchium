import NotchiumClipboardFeature
import NotchiumCore
import NotchiumFocusFeature
import SwiftUI

struct ClipboardSettingsSection: View {
    @Bindable var model: ClipboardModel

    var body: some View {
        Section("Clipboard") {
            Toggle("Capture clipboard history", isOn: $model.captureEnabled)
            Picker("History size", selection: $model.historyLimit) {
                ForEach(ClipboardModel.limitOptions, id: \.self) { Text("\($0) items").tag($0) }
            }
            Picker("Keep items for", selection: $model.retention) {
                ForEach(ClipboardRetention.allCases) { Text($0.title).tag($0) }
            }
            HStack {
                Button("Clear History") { model.clear() }
                    .disabled(model.storageState != .available)
                Button("Clear All, Including Pinned", role: .destructive) { model.clear(includingPinned: true) }
                    .disabled(model.storageState != .available)
            }
            if let message = model.storageState.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Try Again", action: model.retryStorage)
            }
            Text("History is stored on this Mac with best-effort encryption. Clipboard sensitivity and password-manager exclusions are best effort. Turning capture off keeps saved history. Pinned items stay until you remove them.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FocusSettingsSection: View {
    @Bindable var focus: FocusModeModel
    @Bindable var timer: PomodoroModel

    var body: some View {
        Section("Focus") {
            LabeledContent("macOS Focus", value: statusText)
            if focus.availability == .unavailable(.unsupportedDistribution) {
                Text("Focus status isn’t available to Notchium in this version, so it can’t automatically quiet routine interruptions or show Focus changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Reduce Notchium interruptions while Focus is on", isOn: $focus.reducesInterruptions)
            Text("Routine events (device connections, charging, early calendar reminders, screenshots) stay quiet. Critical battery, meetings starting soon, timer completion, transfers and your own actions still appear.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Turn on Focus during Focus Timer sessions", isOn: $focus.timerControlsFocus)
            if focus.timerControlsFocus {
                shortcutPicker("Turn on with", selection: $focus.focusOnShortcut)
                shortcutPicker("Turn off with", selection: $focus.focusOffShortcut)
                Text("macOS doesn’t let apps switch Focus directly. Choose two shortcuts that use the Set Focus action. A Focus you turned on yourself is never turned off.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = focus.shortcutError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .task(id: focus.timerControlsFocus) {
            if focus.timerControlsFocus { await focus.refreshShortcuts() }
        }

        Section("Focus Timer") {
            Picker("Collapsed notch while Music plays", selection: $timer.collapsedPreference) {
                ForEach(CollapsedTimerPreference.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper("Focus: \(timer.configuration.focusMinutes) min",
                    value: $timer.configuration.focusMinutes, in: PomodoroConfiguration.focusMinutesRange, step: 5)
            Stepper("Short break: \(timer.configuration.shortBreakMinutes) min",
                    value: $timer.configuration.shortBreakMinutes, in: PomodoroConfiguration.shortBreakMinutesRange)
            Stepper("Long break: \(timer.configuration.longBreakMinutes) min",
                    value: $timer.configuration.longBreakMinutes, in: PomodoroConfiguration.longBreakMinutesRange, step: 5)
            Stepper("Long break every \(timer.configuration.sessionsPerCycle) focus session\(timer.configuration.sessionsPerCycle == 1 ? "" : "s")",
                    value: $timer.configuration.sessionsPerCycle, in: PomodoroConfiguration.sessionsPerCycleRange)
                .accessibilityIdentifier("notchium.pomodoro.longBreakCadence")
            HStack {
                Picker("Completion sound", selection: $timer.completionSound) {
                    ForEach(PomodoroSound.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("notchium.pomodoro.completionSound")
                Button("Preview", systemImage: "speaker.wave.2", action: timer.previewCompletionSound)
                    .disabled(timer.completionSound == .none)
                    .accessibilityIdentifier("notchium.pomodoro.previewSound")
            }
            Button("Restore Timer Defaults") { timer.configuration = .standard }
                .disabled(timer.configuration == .standard)
        }
    }

    private var statusText: String {
        switch focus.availability {
        case .unavailable(.permissionDenied): "Not allowed (System Settings → Privacy & Security → Focus)"
        case .unavailable(.permissionNotDetermined): "Waiting for permission"
        case .unavailable(.unsupportedDistribution): "Unavailable"
        case .unavailable, .limited: "Unavailable"
        case .available: focus.isFocused == true ? "On" : "Off"
        }
    }

    private func shortcutPicker(_ title: String, selection: Binding<ExistingShortcut?>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(ExistingShortcut?.none)
            ForEach(shortcuts(including: selection.wrappedValue)) { shortcut in
                Text(shortcut.name).tag(ExistingShortcut?.some(shortcut))
            }
        }
    }

    /// Keeps a saved choice listed even before the Shortcuts list has loaded.
    private func shortcuts(including selected: ExistingShortcut?) -> [ExistingShortcut] {
        guard let selected, !focus.availableShortcuts.contains(selected) else { return focus.availableShortcuts }
        return [selected] + focus.availableShortcuts
    }
}
