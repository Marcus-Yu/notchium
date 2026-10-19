import SwiftUI
import NotchiumCore

struct PermissionChecklist: View {
    let model: OnboardingModel
    let allowsReview: Bool
    private let groups = ["Permissions granted", "Requirements completed", "Exceptions reviewed", "Needs attention"]

    var body: some View {
        ForEach(groups, id: \.self) { group in
            let items = SetupPermission.allCases.filter { groupName($0) == group }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(group).font(.headline)
                    ForEach(items) { permission in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: permission.symbol).frame(width: 22).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(permission.title).fontWeight(.medium)
                                Text(permission.summary).font(.callout).foregroundStyle(.secondary)
                                if let status = model.statuses[permission] {
                                    PermissionStatusLabel(status: status, reviewed: model.isSatisfied(permission))
                                    if !status.detail.isEmpty, [.granted, .denied, .restricted, .needsSystemSettings,
                                                               .needsFullAccess, .requiresApplication, .unavailable].contains(status.authorization) {
                                        Text(status.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if permission == .clipboard, let enabled = model.state.clipboardChoice {
                                    Text(enabled ? "Your choice: monitoring enabled after setup." : "Your choice: monitoring stays off.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if permission == .clipboardAccess, model.state.clipboardChoice == false {
                                    Text("Monitoring is off. Any ungranted OS access is an explicit inactive-feature exception.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            if allowsReview {
                                Button("Review") { model.select(permission) }
                                    .accessibilityLabel("Review \(permission.title)")
                                    .accessibilityIdentifier("notchium.setup.review.\(permission.rawValue)")
                            }
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private func groupName(_ permission: SetupPermission) -> String {
        guard let status = model.statuses[permission] else { return "Needs attention" }
        if status.authorization == .granted { return "Permissions granted" }
        if status.authorization == .selectionSaved || (permission == .clipboard && model.isSatisfied(permission)) {
            return "Requirements completed"
        }
        return model.isSatisfied(permission) ? "Exceptions reviewed" : "Needs attention"
    }
}

struct PermissionStatusLabel: View {
    let status: SetupPermissionStatus
    let reviewed: Bool
    var body: some View {
        Label {
            Text(status.authorization.label + (reviewed && status.authorization.acceptsAcknowledgment ? " · Reviewed" : ""))
        } icon: {
            Image(systemName: symbol)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(status.authorization == .granted ? Color.green : Color.secondary)
        .accessibilityElement(children: .combine)
    }
    private var symbol: String {
        switch status.authorization {
        case .granted: "checkmark.circle.fill"
        case .denied, .needsSystemSettings: "exclamationmark.circle"
        case .selectionSaved: "folder.badge.checkmark"
        default: "info.circle"
        }
    }
}

struct PermissionActionButtons: View {
    let model: OnboardingModel
    let permission: SetupPermission
    let status: SetupPermissionStatus
    var body: some View {
        HStack {
            if canRequest {
                Button(actionTitle) { model.request(permission) }
                    .accessibilityIdentifier("notchium.setup.request.\(permission.rawValue)")
            }
            if [.denied, .needsSystemSettings].contains(status.authorization) {
                Button("Open System Settings") { model.openSettings(for: permission) }
            }
            if status.authorization != .notDetermined {
                Button("Refresh Status") { model.refreshStatus() }
            }
        }.disabled(model.isBusy)
    }
    private var canRequest: Bool {
        status.authorization == .notDetermined || status.authorization == .needsFullAccess || status.authorization == .requiresApplication
            || permission == .screenshots || (permission == .volumeKeys && status.authorization != .granted)
    }
    private var actionTitle: String {
        switch permission {
        case .screenshots: "Choose Screenshot Folder…"
        case .spotify where status.authorization == .requiresApplication: "Open Spotify & Request Access"
        case .volumeKeys: "Set Up Accessibility"
        default: "Request Access"
        }
    }
}
