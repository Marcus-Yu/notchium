import SwiftUI
import NotchiumFeature

/// Scene builders stay stable while these views observe deferred controller creation.
@MainActor
struct NotchiumMenuSceneRoot: View {
    @ObservedObject var appDelegate: NotchiumAppDelegate

    var body: some View {
        if let controller = appDelegate.controller {
            NotchiumMenuView(controller: controller)
        } else {
            Text("Starting Notchium…").disabled(true)
        }
    }
}

@MainActor
struct NotchiumSettingsSceneRoot: View {
    @ObservedObject var appDelegate: NotchiumAppDelegate
    let menuBarInsertion: Binding<Bool>

    var body: some View {
        Group {
            if let controller = appDelegate.controller {
                if controller.needsOnboardingPresentation {
                    VStack(spacing: 16) {
                        Text("Complete Notchium setup to continue.")
                        Button("Resume Setup…") { controller.showOnboarding() }
                    }.padding(40)
                } else {
                    NotchiumSettingsView(environment: controller.environment,
                                         audioMeter: controller.mediaModel.audioMeter,
                                         waveformAppearance: controller.mediaModel.waveformAppearance,
                                         calendarModel: controller.calendarModel,
                                         menuBarInsertion: menuBarInsertion,
                                         caffeineModel: controller.caffeineModel,
                                         quickActions: controller.quickActions,
                                         clipboardModel: controller.clipboardModel,
                                         focusModeModel: controller.focusModeModel,
                                         pomodoroModel: controller.pomodoroModel,
                                         systemFeedback: controller.systemFeedback,
                                         displayCoordinator: controller.displayCoordinator,
                                         onboarding: controller.onboarding)
#if DEBUG
                        .preferredColorScheme(debugSettingsColorScheme(for: controller))
#endif
                        .background {
                            SettingsWindowLifecycle(onOpenChanged: appDelegate.settingsWindowOpenChanged)
                                .frame(width: 0, height: 0)
                        }
                }
            } else {
                ProgressView("Starting Notchium…").padding(40)
            }
        }
    }

#if DEBUG
    private func debugSettingsColorScheme(for controller: NotchiumApplicationController) -> ColorScheme? {
        switch controller.shellDebugModel.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
#endif
}

#if DEBUG
@MainActor
struct NotchiumDeveloperSceneRoot: View {
    @ObservedObject var appDelegate: NotchiumAppDelegate

    var body: some View {
        if let controller = appDelegate.controller {
            NotchiumDeveloperPanelView(
                model: controller.developerPanelModel,
                shellDebugModel: controller.shellDebugModel,
                presentationModel: controller.displayCoordinator.presentationModel,
                uuids: controller.environment.uuids,
                mediaModel: controller.mediaModel,
                mockMedia: controller.mockMediaProvider,
                realMedia: controller.environment.services.media
            )
        } else {
            ProgressView("Starting Notchium…")
        }
    }
}
#endif
