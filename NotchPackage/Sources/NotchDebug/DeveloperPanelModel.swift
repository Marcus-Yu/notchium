#if DEBUG
import Foundation
import NotchCore
import NotchDiagnostics
import NotchPersistence
import NotchServices
import Observation

@MainActor
@Observable
public final class DeveloperPanelModel {
    public var providerModes: [ServiceKind: ProviderMode]
    public var simulatedPermissions: [PermissionKind: PermissionState]
    public private(set) var capabilitySnapshot: [ServiceKind: FeatureAvailability]
    public private(set) var syntheticActivities: [ActivityEvent]
    public private(set) var lastRetentionReport: RetentionReport?

    @ObservationIgnored private let services: ServiceRegistry
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private let uuids: any UUIDGenerating
    @ObservationIgnored private let persistence: any PersistenceStoring
    @ObservationIgnored private let logger: any AppLogging

    public init(
        services: ServiceRegistry,
        clock: any AppClock,
        uuids: any UUIDGenerating,
        persistence: any PersistenceStoring,
        logger: any AppLogging
    ) {
        self.services = services
        self.clock = clock
        self.uuids = uuids
        self.persistence = persistence
        self.logger = logger
        providerModes = Dictionary(
            uniqueKeysWithValues: ServiceKind.allCases.map { ($0, .real) }
        )
        simulatedPermissions = Dictionary(
            uniqueKeysWithValues: PermissionKind.allCases.map { ($0, .notDetermined) }
        )
        capabilitySnapshot = [:]
        syntheticActivities = []
    }

    public func setProviderMode(_ mode: ProviderMode, for service: ServiceKind) {
        providerModes[service] = mode
    }

    public func setPermissionState(_ state: PermissionState, for permission: PermissionKind) {
        simulatedPermissions[permission] = state
    }

    public func inspectCapabilities() async {
        var snapshot: [ServiceKind: FeatureAvailability] = [:]
        for service in ServiceKind.allCases {
            snapshot[service] = await services.availability(for: service)
        }
        capabilitySnapshot = snapshot
    }

    public func createSyntheticActivity(_ kind: ActivityKind) async {
        let event = ActivityEvent(
            id: await uuids.next(),
            kind: kind,
            occurredAt: await clock.now()
        )
        syntheticActivities.append(event)
        await logger.record(.syntheticActivityCreated, level: .debug)
    }

    public func runRetentionCleanup() async throws {
        let report = try await persistence.performRetentionCleanup(
            policy: .productDefault,
            referenceDate: await clock.now()
        )
        lastRetentionReport = report
        await logger.record(.retentionCleanupCompleted, level: .debug)
    }
}
#endif
