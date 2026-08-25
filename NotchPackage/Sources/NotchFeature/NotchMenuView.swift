import AppKit
import NotchCore
import SwiftUI

public struct NotchMenuView: View {
    @Bindable private var controller: NotchApplicationController
#if DEBUG
    @Environment(\.openWindow) private var openWindow
#endif

    public init(controller: NotchApplicationController) {
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

            Button("Quit Notch") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
