import NotchiumCore
#if DEBUG
import NotchiumDebug
#endif
import NotchiumDiagnostics
import NotchiumDynamicIsland
import Observation

public enum ShellPlacement: String, Equatable, Sendable {
    case builtInNotch
    case menuBarFallback
}

@MainActor
@Observable
public final class NotchiumApplicationController {
    public let environment: AppEnvironment
    public let panelCoordinator: NotchiumPanelCoordinator
    public private(set) var isRunning = false
    public private(set) var shellPlacement: ShellPlacement = .menuBarFallback

#if DEBUG
    public let developerPanelModel: DeveloperPanelModel
#endif

    public init(
        environment: AppEnvironment,
        panelCoordinator: NotchiumPanelCoordinator = NotchiumPanelCoordinator()
    ) {
        self.environment = environment
        self.panelCoordinator = panelCoordinator
#if DEBUG
        developerPanelModel = DeveloperPanelModel(
            services: environment.services,
            clock: environment.clock,
            uuids: environment.uuids,
            persistence: environment.persistence,
            logger: environment.logger
        )
#endif
    }

    public static func production() -> NotchiumApplicationController {
        NotchiumApplicationController(environment: .production())
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        panelCoordinator.start()
        shellPlacement = panelCoordinator.hasBuiltInNotch
            ? .builtInNotch
            : .menuBarFallback

        let logger = environment.logger
        Task { await logger.record(.applicationStarted, level: .notice) }
    }

    public func stop() {
        guard isRunning else { return }
        panelCoordinator.stop()
        isRunning = false

        let logger = environment.logger
        Task { await logger.record(.applicationStopped, level: .notice) }
    }
}
