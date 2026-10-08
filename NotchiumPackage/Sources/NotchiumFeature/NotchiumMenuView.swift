import AppKit
import NotchiumCore
import SwiftUI

public struct NotchiumMenuView: View {
    @Bindable private var controller: NotchiumApplicationController
    @Environment(\.openSettings) private var openSettings
#if DEBUG
    @Environment(\.openWindow) private var openWindow
#endif

    public init(controller: NotchiumApplicationController) {
        self.controller = controller
    }

    public var body: some View {
        Group {
            Button("Open Notchium") { controller.displayCoordinator.openForKeyboard() }

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
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
