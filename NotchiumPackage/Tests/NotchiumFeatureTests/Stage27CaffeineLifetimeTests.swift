import Foundation
import NotchiumCore
@testable import NotchiumServices
import Synchronization
import XCTest

final class Stage27CaffeineLifetimeTests: XCTestCase {
    func testShutdownDuringAssertionCreationCannotReactivateCaffeine() async {
        await verifyShutdownDuringCreation(cancelOperation: false)
        await verifyShutdownDuringCreation(cancelOperation: true)
    }

    private func verifyShutdownDuringCreation(cancelOperation: Bool) async {
        let began = expectation(description: "Native assertion creation began")
        let resumeCreation = DispatchSemaphore(value: 0)
        let released = Mutex<[UInt32]>([])
        let service = RealCaffeineService(createAssertion: { _ in
            began.fulfill()
            // Simulates a blocking IOKit call; test orchestration awaits explicit events.
            resumeCreation.wait()
            return 42
        }, releaseAssertion: { id in released.withLock { $0.append(id) } })
        defer { service.shutdown() }
        let operation = Task { try await service.setMode(.systemAndDisplay) }
        await fulfillment(of: [began], timeout: 2)
        service.shutdown()
        if cancelOperation { operation.cancel() }
        resumeCreation.signal()
        let result = await operation.result
        if case .success = result { XCTFail("A superseded creation must not commit after shutdown") }
        let updates = await service.updates()
        var iterator = updates.makeAsyncIterator()
        let snapshot = await iterator.next()
        XCTAssertEqual(snapshot?.mode, .off)
        XCTAssertEqual(released.withLock { $0 }, [42], "Release the late assertion exactly once")
    }
}
