import NotchiumCore
#if DEBUG
import NotchiumDebug
#endif
import NotchiumDiagnostics
import NotchiumDynamicIsland
import Observation
import NotchiumMediaFeature
import NotchiumServices

@MainActor
@Observable
public final class NotchiumApplicationController {
    public let environment: AppEnvironment
    public let displayCoordinator: NotchiumDisplayCoordinator
    public let mediaModel: MediaFeatureModel
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
        mediaModel = MediaFeatureModel(provider: environment.services.media,
                                       coordinator: displayCoordinator.presentationModel.activityCoordinator)
        displayCoordinator.presentationModel.mediaRenderer = mediaModel
    }

    public static func production() -> NotchiumApplicationController {
        NotchiumApplicationController(environment: .production())
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        displayCoordinator.start()
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
        displayCoordinator.stop()
        isRunning = false

        let logger = environment.logger
        Task { await logger.record(.applicationStopped, level: .notice) }
    }
}
