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
            Label("Stage 2 shell", systemImage: "checkmark.seal")
            Text(shellStatus)
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

    private var shellStatus: String {
        guard let placement = controller.displayCoordinator.shellPlacement else {
            return "Menu-bar fallback active"
        }
        switch placement.mode {
        case .physicalNotch:
            return "Physical notch shell on \(placement.display.name)"
        case .virtualPill:
            return "Virtual pill on \(placement.display.name)"
        }
    }
}
