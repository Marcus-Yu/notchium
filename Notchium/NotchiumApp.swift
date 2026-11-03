import AppKit
import Combine
import SwiftUI
import NotchiumFeature
import NotchiumServices

@MainActor
final class NotchiumAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var controller: NotchiumApplicationController?
    private var startupTask: Task<Void, Never>?
    private var isSettingsWindowOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        startupTask = Task { [weak self] in
            do {
                let outcome = try await ApplicationInstanceCoordinator().waitForOlderInstancesToExit()
                guard !Task.isCancelled, let self else { return }
                self.startupTask = nil
                switch outcome {
                case .ready: self.startController()
                case .superseded: NSApplication.shared.terminate(nil)
                case .terminationRefused, .timedOut:
                    let alert = NSAlert()
                    alert.messageText = "Notchium couldn’t restart"
                    alert.informativeText = "Another copy is still running. Quit Notchium from its menu, then reopen this copy."
                    alert.addButton(withTitle: "Quit")
                    alert.runModal()
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                // Termination cancels admission before any application services exist.
                if !Task.isCancelled { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private func startController() {
        let controller = NotchiumApplicationController.production()
        self.controller = controller
        let needsSetup = controller.needsOnboardingPresentation
        NSApplication.shared.setActivationPolicy(isSettingsWindowOpen || needsSetup ? .regular : .accessory)
#if DEBUG
        print("Notchium launched; bundle=\(Bundle.main.bundleIdentifier ?? "unknown"); macOS=\(ProcessInfo.processInfo.operatingSystemVersionString); activationPolicy=\(NSApp.activationPolicy().rawValue); LSUIElement=\(String(describing: Bundle.main.object(forInfoDictionaryKey: "LSUIElement")))")
        // Diagnostic evidence only. Never overwrite macOS-owned visibility preferences.
        let statusPreferences = UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("NSStatusItem Visible") }
        print("Saved status-item visibility: \(statusPreferences)")
#endif
        controller.start()
    }

    func settingsWindowOpenChanged(_ isOpen: Bool) {
        isSettingsWindowOpen = isOpen
        guard let controller else { return }
        let application = NSApplication.shared
        let policy: NSApplication.ActivationPolicy = isOpen || controller.needsOnboardingPresentation ? .regular : .accessory
        guard application.activationPolicy() != policy,
              application.setActivationPolicy(policy) else { return }
        if isOpen { application.activate() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
        startupTask = nil
        controller?.stop()
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
            NotchiumMenuSceneRoot(appDelegate: appDelegate)
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
            NotchiumSettingsSceneRoot(appDelegate: appDelegate, menuBarInsertion: menuBarInsertion)
        }

#if DEBUG
        Window("Developer Panel", id: "developer-panel") {
            NotchiumDeveloperSceneRoot(appDelegate: appDelegate)
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
