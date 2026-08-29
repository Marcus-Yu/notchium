#if DEBUG
import NotchiumCore
import NotchiumDesignSystem
import NotchiumServices
import SwiftUI

public struct DeveloperPanelView<ShellContent: View>: View {
    @Bindable private var model: DeveloperPanelModel
    private let shellContent: ShellContent

    public init(
        model: DeveloperPanelModel,
        @ViewBuilder shellContent: () -> ShellContent
    ) {
        self.model = model
        self.shellContent = shellContent()
    }

    public var body: some View {
        TabView {
            shellContent
                .tabItem { Label("Shell", systemImage: "capsule") }

            providers
                .tabItem { Label("Providers", systemImage: "shippingbox") }

            permissions
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            activities
                .tabItem { Label("Activities", systemImage: "waveform.path.ecg") }

            diagnostics
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .padding(NotchiumDesignMetrics.standardSpacing)
        .frame(minWidth: 640, minHeight: 440)
    }

    private var providers: some View {
        Form {
            Section("Provider selection") {
                ForEach(ServiceKind.allCases, id: \.self) { service in
                    Picker(service.rawValue, selection: providerBinding(for: service)) {
                        ForEach(ProviderMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }
            }

            Text("Selections are an injectable development configuration; production flags cannot be changed here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var permissions: some View {
        Form {
            Section("Permission simulation") {
                ForEach(PermissionKind.allCases, id: \.self) { permission in
                    Picker(permission.rawValue, selection: permissionBinding(for: permission)) {
                        ForEach(PermissionState.allCases, id: \.self) { state in
                            Text(state.rawValue).tag(state)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var activities: some View {
        Form {
            Section("Synthetic activities") {
                ForEach(ActivityKind.allCases, id: \.self) { kind in
                    Button("Emit \(kind.rawValue)") {
                        Task { await model.createSyntheticActivity(kind) }
                    }
                }
            }

            LabeledContent("Session count", value: "\(model.syntheticActivities.count)")
        }
        .formStyle(.grouped)
    }

    private var diagnostics: some View {
        Form {
            Section("Capabilities") {
                Button("Refresh capability snapshot") {
                    Task { await model.inspectCapabilities() }
                }
                LabeledContent("Inspected services", value: "\(model.capabilitySnapshot.count)")
            }

            Section("Retention") {
                Button("Run cleanup") {
                    Task { try? await model.runRetentionCleanup() }
                }
                LabeledContent(
                    "Removed records",
                    value: "\((model.lastRetentionReport?.removedClipboardItems ?? 0) + (model.lastRetentionReport?.removedFocusRecords ?? 0))"
                )
            }

            Text("Diagnostics are identifiers and states only. Feature payloads are never logged.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func providerBinding(for service: ServiceKind) -> Binding<ProviderMode> {
        Binding(
            get: { model.providerModes[service, default: .real] },
            set: { model.setProviderMode($0, for: service) }
        )
    }

    private func permissionBinding(for permission: PermissionKind) -> Binding<PermissionState> {
        Binding(
            get: { model.simulatedPermissions[permission, default: .notDetermined] },
            set: { model.setPermissionState($0, for: permission) }
        )
    }
}
#endif
