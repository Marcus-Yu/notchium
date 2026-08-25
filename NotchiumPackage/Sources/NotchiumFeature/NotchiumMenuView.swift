import AppKit
import NotchiumCore
import SwiftUI

public struct NotchiumMenuView: View {
    @Bindable private var controller: NotchiumApplicationController
#if DEBUG
    @Environment(\.openWindow) private var openWindow
#endif

    public init(controller: NotchiumApplicationController) {
        self.controller = controller
    }

    public var body: some View {
        Group {
            Label("Stage 1 architecture", systemImage: "checkmark.seal")
            Text(controller.shellPlacement == .builtInNotch
                 ? "Built-in notch shell active"
                 : "Menu-bar fallback active")
                .foregroundStyle(.secondary)

            Divider()

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }

#if DEBUG
            Button {
                openWindow(id: "developer-panel")
            } label: {
                Label("Developer Panel", systemImage: "hammer")
            }
#endif

            Divider()

            Button("Quit Notchium") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
