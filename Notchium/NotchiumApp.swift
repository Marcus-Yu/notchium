import AppKit
import SwiftUI
import NotchiumFeature

@MainActor
final class NotchiumAppDelegate: NSObject, NSApplicationDelegate {
    let controller = NotchiumApplicationController.production()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
#if DEBUG
        print("Notchium launched; bundle=\(Bundle.main.bundleIdentifier ?? "unknown"); macOS=\(ProcessInfo.processInfo.operatingSystemVersionString); activationPolicy=\(NSApp.activationPolicy().rawValue); LSUIElement=\(String(describing: Bundle.main.object(forInfoDictionaryKey: "LSUIElement")))")
        // Diagnostic evidence only. Never overwrite macOS-owned visibility preferences.
        let statusPreferences = UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("NSStatusItem Visible") }
        print("Saved status-item visibility: \(statusPreferences)")
#endif
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

    init() {
#if DEBUG
        print("Initial isMenuBarExtraInserted=true")
#endif
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInsertion) {
            NotchiumMenuView(controller: appDelegate.controller)
        } label: {
            Label("Notchium", systemImage: "capsule.fill")
                .onAppear {
#if DEBUG
                    print("MenuBarExtra label appeared; isMenuBarExtraInserted=\(isMenuBarExtraInserted)")
#endif
                }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            NotchiumSettingsView(environment: appDelegate.controller.environment,
                                 audioMeter: appDelegate.controller.mediaModel.audioMeter,
                                 calendarModel: appDelegate.controller.calendarModel,
                                 menuBarInsertion: menuBarInsertion)
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

    private var menuBarInsertion: Binding<Bool> {
        Binding(
            get: { isMenuBarExtraInserted },
            set: { value in
                guard isMenuBarExtraInserted != value else { return }
#if DEBUG
                print("MenuBarExtra insertion changed: \(value)")
                if !value {
                    print("MenuBarExtra removed/hidden by macOS. Respecting visibility; restore explicitly in Notchium Settings → Show menu-bar icon. Also check System Settings → Menu Bar.")
                }
#endif
                isMenuBarExtraInserted = value
            }
        )
    }
}
