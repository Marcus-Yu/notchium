import AppKit
import Synchronization
import XCTest
@testable import NotchiumClipboardFeature
@testable import NotchiumServices

@MainActor
final class Stage22ClipboardTests: XCTestCase {
    func testLateImageCannotOvertakeNewerClipboardText() async {
        let board = NSPasteboard(name: .init("notchium.stage22.\(UUID())"))
        defer { board.releaseGlobally() }
        let gate = ClipboardDecodeGate()
        let service = RealClipboardService(pasteboard: board, processImage: { await gate.decode($0) })
        let stream = await service.captures()
        var captures: [ClipboardCapture] = []
        let textArrived = expectation(description: "new text arrives")
        let collector = Task {
            for await capture in stream {
                captures.append(capture)
                if capture.content == .text("newer") { textArrived.fulfill() }
            }
        }
        defer { collector.cancel() }
        board.clearContents()
        board.setData(Data([1]), forType: .png)
        service.poll()
        await gate.waitForDecode()
        board.clearContents()
        board.setString("newer", forType: .string)
        service.poll()
        await fulfillment(of: [textArrived], timeout: 2)
        await gate.release()
        await drainMainActorTasks()
        XCTAssertEqual(captures.map(\.content), [.text("newer")])
    }

    func testOwnClipboardWriteInvalidatesAnInFlightImage() async {
        let board = NSPasteboard(name: .init("notchium.stage22.\(UUID())"))
        defer { board.releaseGlobally() }
        let gate = ClipboardDecodeGate()
        let service = RealClipboardService(pasteboard: board, processImage: { await gate.decode($0) })
        let stream = await service.captures()
        var captures: [ClipboardCapture] = []
        let collector = Task { for await capture in stream { captures.append(capture) } }
        defer { collector.cancel() }
        board.clearContents()
        board.setData(Data([1]), forType: .png)
        service.poll()
        await gate.waitForDecode()
        await service.write(.text("own copy"))
        await gate.release()
        await drainMainActorTasks()
        XCTAssertTrue(captures.isEmpty)
    }

    func testUnchangedPageVisitsDoNotRewriteOrRescanHistory() {
        let store = CountingClipboardStore()
        let name = "notchium.stage22.\(UUID())"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let model = ClipboardModel(service: MockClipboardService(), store: store, preferences: preferences)
        for _ in 0..<100 { model.setVisible(true); model.setVisible(false) }
        XCTAssertEqual(store.writes, 0)
        XCTAssertEqual(store.cleanups, 1, "One startup orphan cleanup, no scans for unchanged content")
    }
}

private actor ClipboardDecodeGate {
    private var pending: CheckedContinuation<ClipboardContent?, Never>?
    func decode(_ data: Data) async -> ClipboardContent? {
        await withCheckedContinuation { pending = $0 }
    }
    func waitForDecode() async { while pending == nil { await Task.yield() } }
    func release() {
        pending?.resume(returning: .image(png: Data([1]), thumbnail: Data([1]), pixelSize: CGSize(width: 1, height: 1)))
        pending = nil
    }
}

private final class CountingClipboardStore: ClipboardStoring, Sendable {
    private let counts = Mutex((writes: 0, cleanups: 0))
    var writes: Int { counts.withLock { $0.writes } }
    var cleanups: Int { counts.withLock { $0.cleanups } }
    func loadItems() -> [ClipboardItem] { [] }
    func saveItems(_ items: [ClipboardItem]) { counts.withLock { $0.writes += 1 } }
    func saveImage(_ png: Data, id: UUID) {}
    func loadImage(id: UUID) -> Data? { nil }
    func removeImages(except ids: Set<UUID>) { counts.withLock { $0.cleanups += 1 } }
}
