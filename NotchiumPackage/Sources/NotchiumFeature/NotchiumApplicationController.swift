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
import NotchiumKeyboardLockFeature
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
    public let caffeineModel: CaffeineControlModel
    public let keyboardLockModel: KeyboardLockControlModel
    public var mediaModel: MediaSessionController { mediaSessionController }
#if DEBUG
    public let mockMediaProvider = MockMediaProvider()
#endif
    @ObservationIgnored private var mediaConnectionTask: Task<Void, Never>?
    public private(set) var isRunning = false

#if DEBUG
    public let developerPanelModel: DeveloperPanelModel
    public let shellDebugModel: NotchShellDebugModel
#endif

    public init(environment: AppEnvironment) {
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
        caffeineModel = CaffeineControlModel(service: environment.services.caffeine)
        keyboardLockModel = KeyboardLockControlModel(service: environment.services.keyboardLock)
        audioModel.onHUD = { [weak presentation = displayCoordinator.presentationModel] hud in
            presentation?.showAudioHUD(hud)
        }
        displayCoordinator.presentationModel.mediaRenderer = mediaModel
        displayCoordinator.presentationModel.calendarRenderer = calendarModel
        displayCoordinator.presentationModel.audioRenderer = audioModel
        displayCoordinator.presentationModel.caffeineController = caffeineModel
        displayCoordinator.presentationModel.keyboardLockController = keyboardLockModel
    }

    public static func production() -> NotchiumApplicationController {
        NotchiumApplicationController(environment: .production())
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        displayCoordinator.start()
        if environment.featureFlags[.calendar] { calendarModel.start() }
        if environment.featureFlags[.audioDevices] { audioModel.start() }
        if environment.featureFlags[.caffeine] { caffeineModel.start() }
        if environment.featureFlags[.keyboardLock] { keyboardLockModel.start() }
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
        mediaModel.stop()
        calendarModel.stop()
        audioModel.stop()
        caffeineModel.stop()
        keyboardLockModel.stop()
        if let real = environment.services.media as? RealMediaProvider {
            Task { await real.shutdown() }
        }
        displayCoordinator.stop()
        isRunning = false

        let logger = environment.logger
        Task { await logger.record(.applicationStopped, level: .notice) }
    }
}
