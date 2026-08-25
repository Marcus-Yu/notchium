import Foundation
import NotchCore
import NotchDiagnostics
import NotchPersistence
import NotchServices

public struct AppEnvironment: Sendable {
    public let services: ServiceRegistry
    public let permissions: any PermissionAuthorizing
    public let persistence: any PersistenceStoring
    public let clock: any AppClock
    public let uuids: any UUIDGenerating
    public let fileSystem: any FileSystemAccessing
    public let logger: any AppLogging
    public let featureFlags: FeatureFlags
    public let distributionProfile: DistributionProfile

    public init(
        services: ServiceRegistry,
        permissions: any PermissionAuthorizing,
        persistence: any PersistenceStoring,
        clock: any AppClock,
        uuids: any UUIDGenerating,
        fileSystem: any FileSystemAccessing,
        logger: any AppLogging,
        featureFlags: FeatureFlags,
        distributionProfile: DistributionProfile
    ) {
        self.services = services
        self.permissions = permissions
        self.persistence = persistence
        self.clock = clock
        self.uuids = uuids
        self.fileSystem = fileSystem
        self.logger = logger
        self.featureFlags = featureFlags
        self.distributionProfile = distributionProfile
    }

    public static func production() -> AppEnvironment {
        AppEnvironment(
            services: .real(),
            permissions: RealPermissionAuthorizer(),
            persistence: RealPersistenceStore(),
            clock: ContinuousAppClock(),
            uuids: SystemUUIDGenerator(),
            fileSystem: SystemFileSystem(),
            logger: UnifiedAppLogger(),
            featureFlags: .stageOne,
            distributionProfile: .current
        )
    }

    public static func mock(
        clock: any AppClock,
        logger: any AppLogging = MockAppLogger()
    ) -> AppEnvironment {
        AppEnvironment(
            services: .mock(),
            permissions: MockPermissionAuthorizer(),
            persistence: MockPersistenceStore(),
            clock: clock,
            uuids: SequenceUUIDGenerator(
                values: [UUID(uuidString: "00000000-0000-0000-0000-000000000001")!]
            ),
            fileSystem: MockFileSystem(
                temporaryURL: URL(fileURLWithPath: "/private/tmp/notch-tests")
            ),
            logger: logger,
            featureFlags: .stageOne,
            distributionProfile: .developerID
        )
    }
}
