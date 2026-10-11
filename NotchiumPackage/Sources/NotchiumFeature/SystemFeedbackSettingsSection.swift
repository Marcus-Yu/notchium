import SwiftUI
import NotchiumServices

struct SystemFeedbackSettingsSection: View {
    let model: SystemFeedbackCoordinator
    @State private var showPermissionEducation = false

    var body: some View {
        Section("System Feedback") {
            Toggle("Replace macOS Volume HUD", isOn: Binding(
                get: { model.replaceVolumeHUD },
                set: { enabled in
                    if enabled { showPermissionEducation = true }
                    else { model.setReplaceVolumeHUD(false) }
                }))
                .disabled(model.volume.mode == .unavailable || (!model.volume.canReplaceVolume && !model.volume.canReplaceMute && !model.replaceVolumeHUD))
                .accessibilityIdentifier("notchium.settings.replaceVolumeHUD")
            Text(statusText).font(.caption).foregroundStyle(.secondary)
            if model.replaceVolumeHUD && model.volume.mode != .activeReplacement {
                Button("Enable Volume Replacement…") { showPermissionEducation = true }
            }
            Text("AirPods use Notchium’s existing connection animation. macOS may also show its connection banner.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("Replace the macOS Volume HUD?", isPresented: $showPermissionEducation) {
            Button("Enable") { model.setReplaceVolumeHUD(true, requestPermission: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Accessibility access lets Notchium handle supported volume and mute keys and show its HUD. Other keys pass through. No keystrokes are stored. If access or output control is unavailable, macOS keeps handling the keys. Allow Notchium in System Settings → Privacy & Security → Accessibility, then return here.")
        }
    }

    private var statusText: String {
        if model.volume.mode == .activeReplacement {
            if !model.volume.canReplaceVolume { return "Handling mute keys. Volume remains handled by macOS on this output." }
            return model.volume.canReplaceMute ? "Handling volume and mute keys for the current output."
                : "Handling volume keys. Mute remains handled by macOS on this output."
        }
        switch model.volume.fallback {
        case .permissionRequired: return "Accessibility access is required. macOS is handling the keys. A changed ad-hoc-signed build may need to be allowed again."
        case .unsupportedOutput: return "This output does not expose supported volume or mute controls. macOS is handling the keys."
        case .tapUnavailable, .tapDisabled, .operationFailed: return "Volume replacement stopped. macOS is handling new keys; enable again to retry."
        case .suspended: return "Volume replacement is paused while the Mac sleeps."
        case nil: return "Uses Notchium’s existing volume feedback. Replacement is available for supported outputs with Accessibility access."
        }
    }
}
