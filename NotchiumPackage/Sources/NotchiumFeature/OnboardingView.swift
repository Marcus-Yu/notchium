import AppKit
import SwiftUI
import NotchiumCore

public struct OnboardingView: View {
    @Bindable private var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let enterApp: () -> Void
    public init(model: OnboardingModel, enterApp: @escaping () -> Void) {
        self.model = model
        self.enterApp = enterApp
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).textSelection(.enabled)
                            .accessibilityIdentifier("notchium.setup.error")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
            .id("\(model.state.step.rawValue)-\(model.current.rawValue)")
            Divider()
            footer.padding(20)
        }
        .background(.background)
        .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 620)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.state.step)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "capsule.fill").font(.system(size: 27)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Notchium").font(.title2.weight(.semibold))
                Text("One-time setup").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(stepLabel).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.horizontal, 28).padding(.vertical, 22)
    }

    private var stepLabel: String {
        switch model.state.step {
        case .welcome: "Welcome"
        case .overview: "Permissions Overview"
        case .permissions: "\((SetupPermission.allCases.firstIndex(of: model.current) ?? 0) + 1) of \(SetupPermission.allCases.count)"
        case .review: "Final Review"
        case .ready: "Ready"
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state.step {
        case .welcome:
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to Notchium").font(.largeTitle.weight(.semibold))
                Text("Your music, calendar, and everyday tools. A little closer.").font(.title3)
                Text("Let’s configure the macOS integrations together. You’ll see every permission, what it enables, and how your data is handled before normal use begins.")
                Text("Setup is saved as you go. You can quit safely and resume here. After completion, review or repair access in Settings → Permissions.")
                    .foregroundStyle(.secondary)
            }.padding(.vertical, 24)
        case .overview:
            Text("Your integrations, in one place").font(.title.weight(.semibold))
            Text("macOS permissions, app choices, and selected-file access are separate. Each step shows its actual status. No capture starts during setup.")
                .foregroundStyle(.secondary)
            PermissionChecklist(model: model, allowsReview: true)
        case .permissions:
            permissionDetail
        case .review:
            Text("Review your setup").font(.title.weight(.semibold))
            Text("Granted permissions are verified with macOS. Reviewed exceptions remain exceptions; acknowledgments do not grant OS access. Spotify may be explicitly reviewed with Continue Without Spotify. Other available required permissions still denied or missing block completion.")
                .foregroundStyle(.secondary)
            PermissionChecklist(model: model, allowsReview: true)
        case .ready:
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.circle").font(.system(size: 42)).foregroundStyle(.tint)
                Text("You’re ready").font(.largeTitle.weight(.semibold))
                Text("Your setup is saved. Notchium will open normally next time.")
                Text("The exceptions you reviewed still apply. Permissions can change in macOS; Settings → Permissions is always available to check and repair access.")
                    .foregroundStyle(.secondary)
            }.padding(.vertical, 24)
        }
    }

    private var permissionDetail: some View {
        let permission = model.current
        let status = model.statuses[permission]
        return VStack(alignment: .leading, spacing: 20) {
            Label(permission.title, systemImage: permission.symbol).font(.title.weight(.semibold))
            Text(permission.summary).font(.title3)
            if let status {
                PermissionStatusLabel(status: status, reviewed: model.isSatisfied(permission))
                if !status.detail.isEmpty { Text(status.detail).foregroundStyle(.secondary).textSelection(.enabled) }
                if permission == .clipboard {
                    HStack {
                        Button("Enable Clipboard History") { model.chooseClipboard(true) }
                            .accessibilityIdentifier("notchium.setup.clipboard.enable")
                        Button("Keep Monitoring Off") { model.chooseClipboard(false) }
                            .accessibilityIdentifier("notchium.setup.clipboard.off")
                    }.disabled(model.isBusy)
                    if let choice = model.state.clipboardChoice {
                        Text(choice ? "Your choice: monitoring enabled after setup." : "Your choice: monitoring stays off.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else if permission == .spotify {
                    PermissionActionButtons(model: model, permission: permission, status: status)
                    if status.authorization != .granted {
                        Text("Local Spotify controls remain unavailable without macOS authorization. You can retry later in Settings → Permissions.")
                            .foregroundStyle(.secondary)
                        Button(model.state.reviewed.contains(.spotify) ? "Continuing Without Spotify" : "Continue Without Spotify") {
                            model.continueWithoutSpotify()
                        }
                        .disabled(model.isBusy || model.state.reviewed.contains(.spotify))
                        .accessibilityIdentifier("notchium.setup.spotify.continueWithout")
                    }
                } else if model.canAcknowledge(permission) {
                    if permission == .clipboardAccess, model.state.clipboardChoice == false {
                        Text("Monitoring is off. Review the current OS state as an inactive-feature exception. This does not grant access.")
                            .foregroundStyle(.secondary)
                    }
                    Button(model.isSatisfied(permission) ? "Reviewed" : "I Understand This Requirement") {
                        model.acknowledgeCurrent()
                    }.disabled(model.isBusy || model.isSatisfied(permission))
                    .accessibilityIdentifier("notchium.setup.acknowledge")
                } else {
                    PermissionActionButtons(model: model, permission: permission, status: status)
                }
            } else { ProgressView("Checking access…") }
        }
    }

    private var footer: some View {
        HStack {
            Button("Quit & Resume Later") { NSApp.terminate(nil) }
                .accessibilityIdentifier("notchium.setup.quit")
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Waiting for macOS") }
            Group {
            switch model.state.step {
            case .welcome:
                Button("Get Started") { model.go(to: .overview) }.keyboardShortcut(.defaultAction)
            case .overview:
                Button("Set Up Permissions") { model.go(to: .permissions) }.keyboardShortcut(.defaultAction)
            case .permissions:
                Button("Review All") { model.go(to: .review) }
                Button("Continue") { model.next() }.keyboardShortcut(.defaultAction)
            case .review:
                Button("Refresh Status") { model.refreshStatus() }
                Button("Finish Setup") { model.finish() }.keyboardShortcut(.defaultAction)
                    .disabled(!model.canFinish).accessibilityIdentifier("notchium.setup.finish")
            case .ready:
                Button("Open Notchium", action: enterApp).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("notchium.setup.open")
            }
            }.disabled(model.isBusy && model.state.step != .ready)
        }
    }
}
