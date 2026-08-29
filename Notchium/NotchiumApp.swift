import AppKit
import SwiftUI
import NotchiumFeature

@MainActor
final class NotchiumAppDelegate: NSObject, NSApplicationDelegate {
    let controller = NotchiumApplicationController.production()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

@main
struct NotchiumApp: App {
    @NSApplicationDelegateAdaptor(NotchiumAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            NotchiumMenuView(controller: appDelegate.controller)
        } label: {
            Label("Notchium", systemImage: "capsule.fill")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            NotchiumSettingsView(environment: appDelegate.controller.environment)
        }

#if DEBUG
        Window("Developer Panel", id: "developer-panel") {
            NotchiumDeveloperPanelView(
                model: appDelegate.controller.developerPanelModel,
                shellDebugModel: appDelegate.controller.shellDebugModel
            )
        }
        .defaultSize(width: 720, height: 520)
#endif
    }
}
