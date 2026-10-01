import Foundation
import NotchiumCore
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumServices
@testable import NotchiumShelfFeature

/// Terminal classification of real `Progress` publications: completion and cancellation are the
/// only evidence, the publication ending never is, and one transfer cannot affect another.
@MainActor
final class TransferTerminalStateTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("transfer-terminal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The traced Zen ordering: five concurrent downloads finish together, three unpublish while
    /// their last delivered update still reads 96–99%, and every file on disk is complete.
    func testConcurrentDownloadsUnpublishedBelowFullWithCompleteFilesAreDone() async {
        let service = RealFileTransferService(folders: [])
        let (received, collector) = await record(service)
        defer { collector.cancel() }
        let activities = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { activities.clearAll() }
        let model = TransferActivityModel(notifications: activities.notifications)

        let lastDelivered: [Int64] = [100, 99, 100, 96, 99]
        let downloads = lastDelivered.indices.map { download("file\($0).bin") }
        let ids = downloads.map { service.published($0) }
        for (progress, last) in zip(downloads, lastDelivered) { progress.completedUnitCount = last }
        for (progress, id) in zip(downloads, ids) {
            write(progress.fileURL!, bytes: 100)
            service.unpublished(progress, id: id)
        }
        await waitUntil { ids.allSatisfy { received.terminal($0) != nil } }
        received.values.forEach(model.receive)

        for id in ids {
            XCTAssertEqual(received.terminal(id)?.phase, .completed)
            XCTAssertEqual(received.terminal(id)?.fraction, 1)
            XCTAssertEqual(received.values.filter { $0.id == id && $0.phase.isTerminal }.count, 1)
        }
        XCTAssertTrue(model.recent.allSatisfy { $0.phase == .completed })
        XCTAssertEqual(model.finishedFiles.count, 5)
        XCTAssertEqual(activities.notifications.active?.content.compactActivity?.trailing, .text("Done"))
    }

    func testUnfinishedEndsWithShortMissingOrCancelledFilesAreStopped() async {
        let service = RealFileTransferService(folders: [])
        let (received, collector) = await record(service)
        defer { collector.cancel() }
        let aborted = download("aborted.bin")      // network failure: partial file kept
        let deleted = download("deleted.bin")      // cancelled in the browser: file removed
        let cancelled = download("cancelled.bin")  // explicit cancellation outranks the bytes
        let ids = [aborted, deleted, cancelled].map { service.published($0) }
        aborted.completedUnitCount = 50
        write(aborted.fileURL!, bytes: 50)
        deleted.completedUnitCount = 80
        cancelled.completedUnitCount = 90
        cancelled.cancel()
        write(cancelled.fileURL!, bytes: 100)
        for (progress, id) in zip([aborted, deleted, cancelled], ids) { service.unpublished(progress, id: id) }
        await waitUntil { ids.allSatisfy { received.terminal($0) != nil } }
        for id in ids { XCTAssertEqual(received.terminal(id)?.phase, .stopped) }
    }

    func testCompletedCancelledAndDiskCompletedTransfersKeepIndependentOutcomes() async {
        let service = RealFileTransferService(folders: [])
        let (received, collector) = await record(service)
        defer { collector.cancel() }
        let activities = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { activities.clearAll() }
        let model = TransferActivityModel(notifications: activities.notifications)
        let a = download("same.bin"), b = download("same.bin"), c = download("same.bin")
        let ids = [a, b, c].map { service.published($0) }
        a.completedUnitCount = 100
        b.completedUnitCount = 40
        c.completedUnitCount = 97
        b.cancel()
        write(c.fileURL!, bytes: 100)
        service.unpublished(c, id: ids[2])
        service.unpublished(b, id: ids[1])
        service.unpublished(a, id: ids[0])
        await waitUntil { ids.allSatisfy { received.terminal($0) != nil } }
        received.values.forEach(model.receive)
        XCTAssertEqual(Set(ids).count, 3, "Identical names keep separate identities")
        XCTAssertEqual(ids.map { id in model.recent.first { $0.id == id }?.phase }, [.completed, .stopped, .completed])
        XCTAssertEqual(activities.notifications.active?.content.compactActivity?.trailing, .text("Stopped"),
                       "The batch result is honest about the one real cancellation")
    }

    func testCompletionSurvivesResetTeardownAndLateCancellation() async {
        let service = RealFileTransferService(folders: [])
        let (received, collector) = await record(service)
        defer { collector.cancel() }
        let progress = download("teardown.bin")
        let id = service.published(progress)
        progress.completedUnitCount = 100
        progress.completedUnitCount = 0
        progress.cancel()
        service.unpublished(progress, id: id)
        await waitUntil { received.terminal(id) != nil }
        XCTAssertEqual(received.terminal(id)?.phase, .completed)
        XCTAssertEqual(received.terminal(id)?.fraction, 1)
    }

    func testCancellationIsNotUndoneByLaterCompletionLikeMetadata() async {
        let service = RealFileTransferService(folders: [])
        let (received, collector) = await record(service)
        defer { collector.cancel() }
        let progress = download("cancel.bin.download")
        let id = service.published(progress)
        progress.completedUnitCount = 30
        progress.cancel()
        progress.completedUnitCount = 100
        progress.fileURL = folder.appendingPathComponent("cancel.bin")
        write(progress.fileURL!, bytes: 100)
        service.unpublished(progress, id: id)
        await waitUntil { received.terminal(id) != nil }
        XCTAssertEqual(received.terminal(id)?.phase, .stopped)
    }

    func testFinalRenameBeforeOrAfterCompletionEvidenceIsDoneWithTheFinalFile() async {
        let service = RealFileTransferService(folders: [])
        let (received, collector) = await record(service)
        defer { collector.cancel() }
        let activities = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { activities.clearAll() }
        let model = TransferActivityModel(notifications: activities.notifications)
        let renamedFirst = download("first.dmg.download"), renamedLast = download("last.dmg.download")
        let ids = [renamedFirst, renamedLast].map { service.published($0) }
        rename(renamedFirst)
        renamedFirst.completedUnitCount = 100
        renamedLast.completedUnitCount = 100
        rename(renamedLast)
        service.unpublished(renamedFirst, id: ids[0])
        service.unpublished(renamedLast, id: ids[1])
        await waitUntil { ids.allSatisfy { received.terminal($0) != nil } }
        received.values.forEach(model.receive)
        XCTAssertEqual(ids.map { received.terminal($0)?.fileURL?.lastPathComponent }, ["first.dmg", "last.dmg"])
        XCTAssertEqual(ids.map { model.finishedFiles[$0]?.lastPathComponent }, ["first.dmg", "last.dmg"])
    }

    func testOldGenerationCallbacksCannotTouchAReusedProgressWithTheSameName() async {
        let service = RealFileTransferService(folders: [])
        let (received, collector) = await record(service)
        defer { collector.cancel() }
        let progress = download("reused.bin")
        let first = service.published(progress)
        progress.completedUnitCount = 100
        service.unpublished(progress, id: first)
        progress.completedUnitCount = 0
        let second = service.published(progress)
        XCTAssertNotEqual(first, second)
        service.unpublished(progress, id: first)
        await drainMainActorTasks()
        XCTAssertNil(received.terminal(second), "Generation N cannot end generation N+1")
        progress.completedUnitCount = 20
        progress.cancel()
        service.unpublished(progress, id: second)
        await waitUntil { received.terminal(second) != nil }
        XCTAssertEqual(received.terminal(first)?.phase, .completed)
        XCTAssertEqual(received.terminal(second)?.phase, .stopped)
    }

    func testDoneHoldsForTheWholeTerminalDwell() async {
        let clock = TestAppClock(now: .now, automaticallyAdvances: false)
        let activities = ActivityCoordinator(clock: clock)
        defer { activities.clearAll() }
        let model = TransferActivityModel(notifications: activities.notifications)
        model.receive(snapshot("t", .active, fraction: 0.97, at: 1))
        model.receive(snapshot("t", .completed, fraction: 1, at: 2))
        await drainMainActorTasks()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(2400))
        model.receive(snapshot("t", .stopped, fraction: 0, at: 3))
        model.receive(snapshot("t", .active, fraction: 0.5, at: 4))
        await drainMainActorTasks()
        XCTAssertEqual(activities.notifications.active?.content.compactActivity?.trailing, .text("Done"))
        await clock.advance(by: .milliseconds(100))
        await waitUntil { activities.primary == nil }
        XCTAssertNil(activities.primary)
        XCTAssertEqual(model.recent.map(\.phase), [.completed])
    }

    // MARK: Deterministic order stress

    private enum Step: CaseIterable { case progress, complete, reset, cancel, rename, unpublish, stale }

    /// Every ordering of the seven callback kinds, applied to three interleaved transfers:
    /// A never cancels, B is a failed download (no completion, short file), C gets everything.
    func testEveryCallbackOrderingKeepsCompletionDoneAndCancellationStopped() async {
        let service = RealFileTransferService(folders: [])
        let (received, collector) = await record(service)
        defer { collector.cancel() }
        let activities = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { activities.clearAll() }
        let orders = permutations(Step.allCases)
        var failures: [String] = []

        // Orderings run in chunks of concurrent publications; each chunk waits for delivery once.
        for chunk in stride(from: 0, to: orders.count, by: 252) {
            var runs: [(order: [Step], plans: [(steps: [Step], fileBytes: Int)], ids: [String])] = []
            for iteration in chunk..<min(chunk + 252, orders.count) {
                let order = orders[iteration]
                let plans: [(steps: [Step], fileBytes: Int)] = [
                    (order.filter { $0 != .cancel }, 100),
                    (order.filter { $0 != .complete }, 40),
                    (order, 100)
                ]
                let downloads = plans.indices.map { download("i\(iteration)-\($0).bin.download") }
                let ids = downloads.map { service.published($0) }
                let rotation = iteration % plans.count
                for index in 0..<order.count {
                    for offset in plans.indices {
                        let transfer = (offset + rotation) % plans.count
                        let steps = plans[transfer].steps
                        guard index < steps.count else { continue }
                        apply(steps[index], to: downloads[transfer], id: ids[transfer], service: service,
                              fileBytes: plans[transfer].fileBytes)
                    }
                }
                runs.append((order, plans, ids))
            }
            let pending = Set(runs.flatMap(\.ids))
            await waitUntil { received.terminalIDs.count >= pending.count }
            XCTAssertEqual(received.terminalIDs, pending, "Exactly the chunk's publications ended; stale callbacks ended nothing")

            for run in runs {
                let ids = run.ids
                let expected = run.plans.map { expectedOutcome($0.steps, fileBytes: $0.fileBytes) }
                let serviceResult = ids.map { received.terminal($0)?.phase }
                let all = TransferActivityModel(notifications: activities.notifications)
                received.delivered(ids).forEach(all.receive)
                let modelResult = ids.map { id in all.recent.first { $0.id == id }?.phase }
                all.reset()
                let pair = TransferActivityModel(notifications: activities.notifications)
                received.delivered([ids[0], ids[2]]).forEach(pair.receive)
                let label = activities.notifications.active?.content.compactActivity?.trailing
                let expectedLabel: NotchCompactActivity.Trailing =
                    expected[0] == .completed && expected[2] == .completed ? .text("Done") : .text("Stopped")
                pair.reset()
                if serviceResult != expected || modelResult != expected || label != expectedLabel {
                    failures.append("\(run.order): expected \(expected) label \(expectedLabel), service \(serviceResult), model \(modelResult), label \(String(describing: label))")
                }
            }
            received.removeAll()
        }

        XCTAssertEqual(orders.count, 5040)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(orders.count) orderings failed:\n" + failures.prefix(5).joined(separator: "\n"))
        print("transfer-terminal stress: permutations=\(orders.count) transfers=\(orders.count * 3) failures=\(failures.count)")
    }

    private func apply(_ step: Step, to progress: Progress, id: String, service: RealFileTransferService, fileBytes: Int) {
        switch step {
        case .progress: progress.completedUnitCount = 50
        case .complete: progress.completedUnitCount = progress.totalUnitCount
        case .reset: progress.completedUnitCount = 0
        case .cancel: progress.cancel()
        case .rename: rename(progress, bytes: fileBytes)
        case .unpublish: service.unpublished(progress, id: id)
        case .stale: service.unpublished(progress, id: UUID().uuidString)
        }
    }

    /// The oracle: the first completion or cancellation before unpublish wins; without either,
    /// a complete file at unpublish is Done and anything else is Stopped.
    private func expectedOutcome(_ steps: [Step], fileBytes: Int) -> TransferPhase {
        var latched: TransferPhase?
        var fileComplete = false
        for step in steps {
            switch step {
            case .complete where latched == nil: latched = .completed
            case .cancel where latched == nil: latched = .stopped
            case .rename: fileComplete = fileBytes == 100
            case .unpublish: return latched ?? (fileComplete ? .completed : .stopped)
            default: break
            }
        }
        return .stopped
    }

    // MARK: Helpers

    private func download(_ name: String) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = folder.appendingPathComponent(name)
        return progress
    }

    /// The browser moves its finished bytes to the final name and updates the published URL.
    private func rename(_ progress: Progress, bytes: Int = 100) {
        let finished = TransferSnapshot.finishedFileURL(progress.fileURL!)
        write(finished, bytes: bytes)
        progress.fileURL = finished
    }

    private func write(_ url: URL, bytes: Int) {
        FileManager.default.createFile(atPath: url.path, contents: Data(count: bytes))
    }

    private func snapshot(_ id: String, _ phase: TransferPhase, fraction: Double, at time: TimeInterval) -> TransferSnapshot {
        .init(id: id, displayName: "file.bin", operation: .downloading, phase: phase, fraction: fraction,
              startedAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: time))
    }

    private func record(_ service: RealFileTransferService) async -> (Received, Task<Void, Never>) {
        let stream = await service.updates()
        let received = Received()
        let task = Task { @MainActor in
            for await snapshot in stream { received.append(snapshot) }
        }
        return (received, task)
    }

    private func permutations<T>(_ items: [T]) -> [[T]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { index in
            var rest = items
            let head = rest.remove(at: index)
            return permutations(rest).map { [head] + $0 }
        }
    }
}

@MainActor private final class Received {
    private(set) var values: [TransferSnapshot] = []
    private(set) var terminalIDs: Set<String> = []
    private var positions: [String: [Int]] = [:]
    func append(_ snapshot: TransferSnapshot) {
        positions[snapshot.id, default: []].append(values.count)
        values.append(snapshot)
        if snapshot.phase.isTerminal { terminalIDs.insert(snapshot.id) }
    }
    func terminal(_ id: String) -> TransferSnapshot? {
        positions[id]?.lazy.map { self.values[$0] }.last { $0.phase.isTerminal }
    }
    /// These transfers' snapshots in the order the service delivered them.
    func delivered(_ ids: [String]) -> [TransferSnapshot] {
        ids.flatMap { positions[$0] ?? [] }.sorted().map { values[$0] }
    }
    func removeAll() { values.removeAll(); positions.removeAll(); terminalIDs.removeAll() }
}
