import AppKit
import SwiftUI
import NotchiumCore

struct PermissionsSettingsSection: View {
    let model: OnboardingModel
    var body: some View {
        Section("Setup") {
            LabeledContent("One-time setup", value: setupDescription)
            Text("Setup completion is saved independently of current macOS permissions. A revoked permission does not restart onboarding.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Refresh All Statuses") { model.refreshStatus() }.disabled(model.isBusy)
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
        ForEach(SetupPermission.allCases) { permission in
            Section(permission.title) {
                Text(permission.summary)
                if let status = model.statuses[permission] {
                    PermissionStatusLabel(status: status, reviewed: model.isSatisfied(permission))
                    if !status.detail.isEmpty { Text(status.detail).font(.callout).foregroundStyle(.secondary) }
                    if permission == .spotify, model.state.reviewed.contains(.spotify), status.authorization != .granted {
                        Text("Setup continued without Spotify. Use Request Access or System Settings to enable it later; your completed setup stays saved.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if permission != .clipboard && !status.authorization.acceptsAcknowledgment {
                        PermissionActionButtons(model: model, permission: permission, status: status)
                    }
                    if permission == .systemAudio || permission == .clipboardAccess {
                        Button("Open Privacy Settings") { model.openSettings(for: permission) }
                    }
                    if permission == .clipboard {
                        Text("Change monitoring and retention in Settings → Clipboard. App consent does not replace macOS pasteboard access.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else { ProgressView("Checking access…") }
            }
        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshStatus()
        }
    }
    private var setupDescription: String {
        switch model.state.completion {
        case .userCompleted: "Completed"
        case .legacyRecognized: "Returning installation · configuration preserved"
        case nil: "Incomplete"
        }
    }
}
