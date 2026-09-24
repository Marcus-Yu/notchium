import NotchiumServices
import SwiftUI

public struct LidAwakeSettingsSection: View {
    let controller: LidAwakeController

    public init(controller: LidAwakeController) { self.controller = controller }

    public var body: some View {
        Section("Closed-lid keep-awake") {
            Toggle("Keep Mac awake with the lid closed", isOn: Binding(
                get: { controller.isEnabled },
                set: { if $0 { controller.enable() } else { controller.disable() } }
            ))
            Text("Applies to both Caffeine modes. Requires administrator approval. Temporarily disables system sleep, including manual Sleep; the built-in display still turns off when closed. Keep the Mac ventilated. Stops below 15% battery or under high thermal pressure.")
                .font(.caption).foregroundStyle(.secondary)
            Text(controller.message).font(.caption)
            if controller.needsApproval {
                Button("Open Login Items & Extensions", action: controller.openApprovalSettings)
            }
            Button("Remove Closed-Lid Helper") {
                Task { await controller.removeHelper() }
            }
        }
    }
}
