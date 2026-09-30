import NotchiumCore
import NotchiumCalendarFeature
import NotchiumAudioFeature
import NotchiumCaffeineFeature
#if DEBUG
import NotchiumDebug
#endif
import NotchiumDiagnostics
import NotchiumDynamicIsland
import Observation
import NotchiumMediaFeature
import NotchiumQuickActionsFeature
import NotchiumShelfFeature
import Foundation
import NotchiumPersistence
import NotchiumServices

@MainActor
@Observable
public final class NotchiumApplicationController {
    public let environment: AppEnvironment
    public let displayCoordinator: NotchiumDisplayCoordinator
    public let mediaSessionController: MediaSessionController
    public let calendarModel: CalendarActivityModel
    public let audioModel: AudioFeatureModel
    public let quickActions: QuickActionsModel
    public let caffeineModel: CaffeineControlModel
    public let filesModel: FilesFeatureModel
    public var mediaModel: MediaSessionController { mediaSessionController }
#if DEBUG
    public let mockMediaProvider = MockMediaProvider()
#endif
    @ObservationIgnored private var mediaConnectionTask: Task<Void, Never>?
    @ObservationIgnored private var batteryTask: Task<Void, Never>?
    public private(set) var isRunning = false

#if DEBUG
    public let developerPanelModel: DeveloperPanelModel
    public let shellDebugModel: NotchShellDebugModel
#endif

    public init(environment: AppEnvironment,
                reminderService: any ReminderService = MockReminderService(),
                shortcutService: any ShortcutService = MockShortcutService(),
                workspace: any QuickActionWorkspace = NativeQuickActionWorkspace(),
                actionStore: QuickActionStore? = nil) {
        self.environment = environment
#if DEBUG
        let shellDebugModel = NotchShellDebugModel()
        self.shellDebugModel = shellDebugModel
        displayCoordinator = NotchiumDisplayCoordinator(
            clock: environment.clock,
            debugModel: shellDebugModel
        )
        developerPanelModel = DeveloperPanelModel(
            services: environment.services,
            clock: environment.clock,
            uuids: environment.uuids,
            persistence: environment.persistence,
            logger: environment.logger
        )
#else
        displayCoordinator = NotchiumDisplayCoordinator(clock: environment.clock)
#endif
        mediaSessionController = MediaSessionController(provider: environment.services.media,
                                       coordinator: displayCoordinator.presentationModel.activityCoordinator,
                                       visibilityClock: environment.clock,
                                       snapshotStore: environment.persistence,
                                       audioMeter: SystemAudioMeter(activityClock: environment.clock))
        calendarModel = CalendarActivityModel(service: environment.services.calendar,
            coordinator: displayCoordinator.presentationModel.activityCoordinator,
            clock: environment.clock)
        audioModel = AudioFeatureModel(devices: environment.services.audioDevices,
                                       processes: environment.services.audioProcesses,
                                       mixer: environment.services.appAudioMixer)
        let store = actionStore ?? QuickActionStore(preferences: .standard)
        let notifications = displayCoordinator.presentationModel.notificationCoordinator
        let runner = QuickActionRunner(store: store, workspace: workspace, shortcuts: shortcutService,
                                       notifications: notifications, clock: environment.clock)
        let reminder = QuickReminderModel(service: reminderService, workspace: workspace, store: store,
                                          notifications: notifications, clock: environment.clock)
        quickActions = QuickActionsModel(store: store, runner: runner, reminder: reminder)
        displayCoordinator.presentationModel.quickActionsRenderer = quickActions
        caffeineModel = CaffeineControlModel(service: environment.services.caffeine)
        filesModel = FilesFeatureModel(transfers: environment.services.transfers,
                                       screenshots: environment.services.screenshot,
                                       shelf: environment.services.shelf,
                                       actions: NativeFileActions(),
                                       activities: displayCoordinator.presentationModel.activityCoordinator)
        displayCoordinator.presentationModel.shelfRenderer = filesModel
        audioModel.onHUD = { [weak presentation = displayCoordinator.presentationModel] hud in
            presentation?.showAudioHUD(hud)
        }
        displayCoordinator.presentationModel.mediaRenderer = mediaModel
        displayCoordinator.presentationModel.calendarRenderer = calendarModel
        displayCoordinator.presentationModel.audioRenderer = audioModel
        displayCoordinator.presentationModel.caffeineController = caffeineModel
    }

    /// Event-driven battery activities; the stream ends when the task is cancelled.
    private func startBatteryActivities() {
        let battery = environment.services.battery
        batteryTask = Task { [weak presentation = displayCoordinator.presentationModel] in
            var policy = BatteryActivityPolicy()
            for await snapshot in await battery.updates() {
                guard !Task.isCancelled else { return }
                switch policy.receive(snapshot) {
                case let .charging(level): presentation?.notificationCoordinator.present(.charging(level: level))
                case let .powerDisconnected(level):
                    presentation?.notificationCoordinator.present(.powerDisconnected(level: level))
                case let .low(level): presentation?.notificationCoordinator.present(.lowBattery(level: level))
                case let .critical(level): presentation?.notificationCoordinator.present(.criticalBattery(level: level))
                case nil: break
                }
            }
        }
    }

    public static func production() -> NotchiumApplicationController {
#if DEBUG
        if CommandLine.arguments.contains("--notchium-stage11-fixture") { return stage11Fixture() }
#endif
        return NotchiumApplicationController(environment: .production(), reminderService: EventKitReminderService(),
                                      shortcutService: AppleShortcutService())
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        displayCoordinator.start()
        if environment.featureFlags[.calendar] { calendarModel.start() }
        if environment.featureFlags[.audioDevices] { audioModel.start() }
        if environment.featureFlags[.caffeine] { caffeineModel.start() }
        if environment.featureFlags[.activities] { startBatteryActivities() }
        if environment.featureFlags[.shelf] { filesModel.start() }
        if environment.featureFlags[.media] {
            mediaModel.start()
            if let real = environment.services.media as? RealMediaProvider {
                mediaConnectionTask = Task { try? await real.connect() }
            }
        }

        let logger = environment.logger
        Task { await logger.record(.applicationStarted, level: .notice) }
    }

    public func stop() {
        guard isRunning else { return }
        mediaConnectionTask?.cancel(); mediaConnectionTask = nil
        batteryTask?.cancel(); batteryTask = nil
        mediaModel.stop()
        calendarModel.stop()
        audioModel.stop()
        caffeineModel.stop()
        filesModel.stop()
        quickActions.runner.stop()
        if let real = environment.services.media as? RealMediaProvider {
            Task { await real.shutdown() }
        }
        displayCoordinator.stop()
        isRunning = false

        let logger = environment.logger
        Task { await logger.record(.applicationStopped, level: .notice) }
    }
}
