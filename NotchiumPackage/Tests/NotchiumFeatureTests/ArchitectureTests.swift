import Foundation
import NotchiumCore
@testable import NotchiumFeature
import NotchiumServices
import NotchiumTestFixtures
import XCTest

@MainActor
final class ArchitectureTests: XCTestCase {
    func testProductionFlagsExposeOnlyTheShell() {
        let flags = FeatureFlags.stageTwoShell

        XCTAssertTrue(flags[.notchShell])
        XCTAssertFalse(flags[.media])
        XCTAssertFalse(flags[.calendar])
        XCTAssertFalse(flags[.keyboardLock])
        XCTAssertFalse(flags[.spotifyAudioWaveform])
    }

    func testEveryRealProviderFailsClosedUntilStageTwo() async {
        let services = ServiceRegistry.real()

        for service in ServiceKind.allCases {
            let availability = await services.availability(for: service)
            XCTAssertEqual(availability, .unavailable(.stageTwoRequired))
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

    func testKeyboardLockPolicyKeepsTheFixedFailOpenContract() {
        let policy = KeyboardLockPolicy.productDefault

        XCTAssertTrue(policy.mouseRemainsUsable)
        XCTAssertTrue(policy.unlockOnTapFailure)
        XCTAssertEqual(policy.emergencyHoldDuration, .seconds(3))
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
            featureFlags: .stageTwoShell,
            distributionProfile: .developerID
        )

        XCTAssertEqual(environment.distributionProfile, .developerID)
        XCTAssertTrue(environment.services.media is MockMediaService)
    }
}
