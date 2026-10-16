import CoreGraphics
import Synchronization
import XCTest
@testable import NotchiumMediaFeature

@MainActor
final class Stage26AudioSessionTests: XCTestCase {
    func testSlowHALStartLeavesMainActorResponsiveAndStaleReconnectCannotUndoStop() async throws {
        let entered = expectation(description: "HAL setup is off MainActor")
        let gate = DispatchSemaphore(value: 0)
        let counts = Mutex((starts: 0, stops: 0))
        let tap = FixtureProcessTap(start: { _ in
            XCTAssertFalse(Thread.isMainThread)
            counts.withLock { $0.starts += 1 }
            entered.fulfill()
            XCTAssertEqual(gate.wait(timeout: .now() + 2), .success)
        }, stop: {
            XCTAssertFalse(Thread.isMainThread)
            counts.withLock { $0.stops += 1 }
        })
        let session = SpotifyProcessTapSession(makeTap: { _ in tap })
        let startup = Task { try await session.replace(processIdentifier: 123, generation: 1, levels: { _ in }) }
        await fulfillment(of: [entered], timeout: 1)
        let stop = Task { await session.stop(generation: 3) }
        gate.signal()
        try await startup.value
        await stop.value
        try await session.replace(processIdentifier: 456, generation: 2, levels: { _ in })
        XCTAssertEqual(counts.withLock { $0.starts }, 1)
        XCTAssertEqual(counts.withLock { $0.stops }, 1)
    }

    func testFailedStartCleansUpBeforeAnotherSessionCanBegin() async throws {
        let stops = Mutex(0)
        let tap = FixtureProcessTap(start: { _ in throw FixtureFailure.failed },
                                    stop: { stops.withLock { $0 += 1 } })
        let session = SpotifyProcessTapSession(makeTap: { _ in tap })
        for generation in [UInt64(1), 2] {
            do {
                try await session.replace(processIdentifier: 123, generation: generation, levels: { _ in })
                XCTFail("The failing native start must propagate its error")
            } catch FixtureFailure.failed { }
        }
        await session.stop(generation: 3)
        XCTAssertEqual(stops.withLock { $0 }, 2)
    }
}

private enum FixtureFailure: Error { case failed }

private final class FixtureProcessTap: SpotifyProcessTapping {
    private let begin: @Sendable (pid_t) throws -> Void
    private let end: @Sendable () -> Void
    init(start: @escaping @Sendable (pid_t) throws -> Void, stop: @escaping @Sendable () -> Void) {
        begin = start; end = stop
    }
    func start(processIdentifier: pid_t) throws { try begin(processIdentifier) }
    func stop() { end() }
}
