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

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }
}

@main
struct NotchiumApp: App {
    @NSApplicationDelegateAdaptor(NotchiumAppDelegate.self) private var appDelegate
    @State private var isMenuBarExtraInserted = true

    var body: some Scene {
        MenuBarExtra(isInserted: $isMenuBarExtraInserted) {
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
                shellDebugModel: appDelegate.controller.shellDebugModel,
                presentationModel: appDelegate.controller.displayCoordinator.presentationModel,
                uuids: appDelegate.controller.environment.uuids,
                mediaModel: appDelegate.controller.mediaModel,
                mockMedia: appDelegate.controller.mockMediaProvider,
                realMedia: appDelegate.controller.environment.services.media
            )
        }
        .defaultSize(width: 720, height: 520)
#endif
    }
}
