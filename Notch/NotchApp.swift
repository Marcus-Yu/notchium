import AppKit
import SwiftUI
import NotchFeature

@MainActor
final class NotchAppDelegate: NSObject, NSApplicationDelegate {
    let controller = NotchApplicationController.production()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(NotchAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            NotchMenuView(controller: appDelegate.controller)
        } label: {
            Label("Notch", systemImage: "capsule.fill")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            NotchSettingsView(environment: appDelegate.controller.environment)
        }

#if DEBUG
        Window("Developer Panel", id: "developer-panel") {
            NotchDeveloperPanelView(model: appDelegate.controller.developerPanelModel)
        }
        .defaultSize(width: 720, height: 520)
#endif
    }
}
