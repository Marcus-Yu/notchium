import Foundation
import NotchiumCore
@testable import NotchiumFeature
import NotchiumServices
import NotchiumTestFixtures
import XCTest

@MainActor
final class ArchitectureTests: XCTestCase {
    func testProductionEnablesEveryRuntimeFlagAndFixturesOmitTheStageNineteenUtilities() {
        let production = FeatureFlags.stageNineteenUtilities
        for flag in FeatureFlag.allCases {
            XCTAssertTrue(production[flag], "\(flag)")
            XCTAssertEqual(FeatureFlags.stageFifteenFiles[flag], ![.clipboard, .camera, .focus].contains(flag), "\(flag)")
        }
        XCTAssertFalse(FeatureFlags(values: [:])[.media])
    }

    func testUnimplementedRealProvidersFailClosedAndMediaRequiresConnection() async {
        let services = ServiceRegistry.real()

        for service in ServiceKind.allCases {
            let availability = await services.availability(for: service)
            // Stages 14–15: Spotlight screenshots, NSProgress transfers and bookmark Shelf are real.
            if [.audioDevices, .caffeine, .screenshot, .downloads, .shelf, .clipboard].contains(service) {
                XCTAssertEqual(availability, .available)
            } else if service == .camera || service == .focus {
                // Stages 17–18: AVFoundation and INFocusStatusCenter; availability follows the user's permission.
                // Focus status also needs the Communication Notifications entitlement (absent in the test runner).
                XCTAssertTrue([.available, .unavailable(.permissionNotDetermined), .unavailable(.permissionDenied),
                               .unavailable(.permissionRestricted), .unavailable(.unsupportedDistribution)]
                    .contains(availability), "\(service): \(availability)")
            } else if service == .battery {
                // Real IOKit source: a laptop reports its battery; a desktop has none.
                XCTAssertTrue([.available, .unavailable(.unsupportedHardware)].contains(availability))
            } else if service == .calendar {
                XCTAssertTrue([.available, .unavailable(.permissionNotDetermined),
                               .unavailable(.permissionDenied), .unavailable(.permissionRestricted)]
                    .contains(availability))
            } else {
                XCTAssertEqual(availability, .unavailable(service == .media ? .permissionNotDetermined : .stageTwoRequired))
            }
        }
    }

    func testEveryMockProviderIsInjectableAndAvailable() async {
        let services = FixtureFactory.serviceRegistry()

        for service in ServiceKind.allCases {
            let availability = await services.availability(for: service)
            XCTAssertEqual(availability, .available)
        }
    }

    func testFakeClockAdvancesDeterministically() async throws {
        let clock = FixtureFactory.clock()

        try await clock.sleep(for: .seconds(15))
        await clock.advance(by: .seconds(5))

        let now = await clock.now()
        let history = await clock.sleepHistory()
        XCTAssertEqual(now, FixtureFactory.referenceDate.addingTimeInterval(20))
        XCTAssertEqual(history, [.seconds(15)])
    }

    func testPermissionRequestsNeverPromptInStageOne() async {
        let authorizer = RealPermissionAuthorizer()

        do {
            _ = try await authorizer.request(.camera)
            XCTFail("Stage 1 unexpectedly allowed a permission request")
        } catch let error as ServiceFailure {
            XCTAssertEqual(error, .permissionRequestsDisabled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFeatureCatalogKeepsSeparateFeatureBoundaries() {
        let identifiers = Set(FeatureCatalog.descriptors.map(\.id))

        XCTAssertEqual(identifiers.count, FeatureCatalog.descriptors.count)
        XCTAssertTrue(identifiers.contains(.shell))
        XCTAssertTrue(identifiers.contains(.media))
        XCTAssertTrue(identifiers.contains(.focus))
    }

    func testApplicationDependenciesCanBeReplacedAtTheRoot() {
        let environment = AppEnvironment(
            services: FixtureFactory.serviceRegistry(),
            permissions: MockPermissionAuthorizer(states: [.camera: .denied]),
            persistence: FixtureFactory.persistence(),
            clock: FixtureFactory.clock(),
            uuids: SequenceUUIDGenerator(
                values: [UUID(uuidString: "00000000-0000-0000-0000-000000000002")!]
            ),
            fileSystem: MockFileSystem(
                temporaryURL: URL(fileURLWithPath: "/private/tmp/notchium-tests")
            ),
            logger: FixtureFactory.logger(),
            featureFlags: FeatureFlags(values: [:]),
            distributionProfile: .developerID
        )

        XCTAssertEqual(environment.distributionProfile, .developerID)
        XCTAssertTrue(environment.services.media is MockMediaService)
    }
}
