import Foundation
import XCTest
@testable import NotchiumServices

@MainActor
final class Stage22TransferStressTests: XCTestCase {
    func testBurstSchedulesOneDeliveryAndLatchesTerminalBeforeDelivery() {
        let samples = TransferSampleBuffer()
        let now = Date()
        var deliveries = 0
        for index in 0..<10_000 {
            if samples.record(.init(id: "one", displayName: "same", operation: .downloading,
                phase: .active, fraction: Double(index) / 10_000, startedAt: now, updatedAt: now)) {
                deliveries += 1
            }
        }
        XCTAssertEqual(deliveries, 1)
        samples.record(.init(id: "one", displayName: "same", operation: .downloading,
            phase: .completed, fraction: 1, startedAt: now, updatedAt: now))
        samples.deliveryHandled()
        XCTAssertFalse(samples.record(.init(id: "one", displayName: "same", operation: .downloading,
            phase: .stopped, fraction: 0, startedAt: now, updatedAt: now)))
        XCTAssertEqual(samples.latest?.phase, .completed)
    }
    func testTenThousandProgressWritesPreserveOneTerminalResult() async {
        let service = RealFileTransferService(folders: [])
        let stream = await service.updates()
        var snapshots: [TransferSnapshot] = []
        let terminal = expectation(description: "terminal result")
        let collector = Task {
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.phase.isTerminal { terminal.fulfill() }
            }
        }
        defer { collector.cancel() }
        let progress = Progress(totalUnitCount: 10_000)
        progress.kind = .file
        let id = service.published(progress)
        for bytes in 1...10_000 { progress.completedUnitCount = Int64(bytes) }
        progress.completedUnitCount = 0
        progress.cancel()
        service.unpublished(progress, id: id)
        await fulfillment(of: [terminal], timeout: 10)
        XCTAssertEqual(snapshots.filter { $0.phase.isTerminal }.map(\.phase), [.completed])
        XCTAssertEqual(Set(snapshots.map(\.id)), [id])
    }
}
