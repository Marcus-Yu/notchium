import Foundation
import NotchiumCore
import NotchiumServices
import Security
import Synchronization
import XCTest
@testable import NotchiumClipboardFeature

@MainActor
final class ClipboardRetryConcurrencyTests: XCTestCase {
    func testStopThenStartDuringInitialLoadCannotOverwriteCommittedHistory() async {
        let firstRead = expectation(description: "initial read started")
        let secondRead = expectation(description: "restart read started")
        let callbacks = Mutex(0)
        let store = GatedClipboardRecoveryStore(loadsAsynchronously: true, started: {
            let count = callbacks.withLock { $0 += 1; return $0 }
            if count == 1 { firstRead.fulfill() } else { secondRead.fulfill() }
        })
        let preferences = preferences()
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let model = ClipboardModel(service: MockClipboardService(), store: store, preferences: preferences,
                                   storageClock: clock)
        defer { model.stop(); preferences.removePersistentDomain(forName: preferencesSuite) }
        await fulfillment(of: [firstRead], timeout: 2)
        model.stop(); model.start()
        XCTAssertEqual(store.attempts, 1, "Canceled native work must finish before another read starts")
        model.receive(ClipboardCapture(content: .text("before hydration"), capturedAt: Date()))
        XCTAssertTrue(model.items.isEmpty)
        let saved = ClipboardItem(content: .text("committed"), capturedAt: Date())
        store.complete(with: [saved])
        await fulfillment(of: [secondRead], timeout: 2)
        model.receive(ClipboardCapture(content: .text("during restart"), capturedAt: Date()))
        XCTAssertTrue(model.items.isEmpty)
        store.complete(with: [saved])
        await awaitStorage(model)
        model.receive(ClipboardCapture(content: .text("after hydration"), capturedAt: Date()))
        XCTAssertEqual(model.items.map(\.preview), ["after hydration", "committed"])
    }

    func testRapidRetryClicksSubmitOnlyOneOperationAndRestoreBeforeCapture() async {
        let loaded = expectation(description: "retry started")
        let store = GatedClipboardRecoveryStore(started: { loaded.fulfill() })
        let preferences = preferences()
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let model = ClipboardModel(service: MockClipboardService(), store: store, preferences: preferences,
                                   storageClock: clock)
        defer { model.stop(); preferences.removePersistentDomain(forName: preferencesSuite) }
        for _ in 0..<100 { model.retryStorage() }
        await fulfillment(of: [loaded], timeout: 2)
        XCTAssertEqual(store.attempts, 1)
        XCTAssertTrue(model.isLoadingStorage)
        model.receive(ClipboardCapture(content: .text("ignored during recovery"), capturedAt: Date()))
        XCTAssertTrue(model.items.isEmpty)
        let saved = ClipboardItem(content: .text("committed"), capturedAt: Date())
        store.complete(with: [saved])
        await awaitStorage(model)
        XCTAssertEqual(model.items, [saved])
        XCTAssertEqual(model.storageState, .available)
    }

    func testSlowKeychainEndsSpinnerWithoutLaunchingDuplicateRetry() async {
        let loaded = expectation(description: "retry started")
        let store = GatedClipboardRecoveryStore(started: { loaded.fulfill() })
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let preferences = preferences()
        let model = ClipboardModel(service: MockClipboardService(), store: store, preferences: preferences,
                                   storageClock: clock)
        defer { model.stop(); preferences.removePersistentDomain(forName: preferencesSuite) }
        model.retryStorage()
        await fulfillment(of: [loaded], timeout: 2)
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(30))
        for _ in 0..<100 where !model.storageNeedsAttention { await Task.yield() }
        XCTAssertTrue(model.storageNeedsAttention)
        model.retryStorage()
        XCTAssertEqual(store.attempts, 1)
        store.complete(with: [])
        await awaitStorage(model)
        XCTAssertFalse(model.storageNeedsAttention)
    }

    func testStoppedModelIgnoresLateRecoveryAndDoesNotWaitForKeychain() async {
        let loaded = expectation(description: "retry started")
        let store = GatedClipboardRecoveryStore(started: { loaded.fulfill() })
        let preferences = preferences()
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let model = ClipboardModel(service: MockClipboardService(), store: store, preferences: preferences,
                                   storageClock: clock)
        defer { preferences.removePersistentDomain(forName: preferencesSuite) }
        model.retryStorage()
        await fulfillment(of: [loaded], timeout: 2)
        model.stop()
        XCTAssertFalse(model.isLoadingStorage)
        XCTAssertEqual(store.flushes, 0, "Shutdown must not wait behind native authorization UI")
        store.complete(with: [ClipboardItem(content: .text("late"), capturedAt: Date())])
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(model.items.isEmpty)
    }

    private var preferencesSuite = ""
    private func preferences() -> UserDefaults {
        preferencesSuite = "notchium.clipboard.retry-tests.\(UUID())"
        return UserDefaults(suiteName: preferencesSuite)!
    }
    private func awaitStorage(_ model: ClipboardModel) async {
        for _ in 0..<10_000 where model.isLoadingStorage { await Task.yield() }
        XCTAssertFalse(model.isLoadingStorage)
    }
}

private final class GatedClipboardRecoveryStore: ClipboardStoring, Sendable {
    private struct State {
        var storage: ClipboardStorageState = .keychainFailure(.read, errSecNotAvailable)
        var attempts = 0
        var flushes = 0
        var continuation: CheckedContinuation<[ClipboardItem], Never>?
    }
    private let value = Mutex(State())
    private let started: @Sendable () -> Void
    let loadsAsynchronously: Bool
    init(loadsAsynchronously: Bool = false, started: @escaping @Sendable () -> Void) {
        self.loadsAsynchronously = loadsAsynchronously
        self.started = started
        if loadsAsynchronously { value.withLock { $0.storage = .available } }
    }
    var state: ClipboardStorageState { value.withLock { $0.storage } }
    var attempts: Int { value.withLock { $0.attempts } }
    var flushes: Int { value.withLock { $0.flushes } }
    func loadItems() -> [ClipboardItem] { [] }
    func loadItemsForRecovery(allowAuthentication: Bool) async -> [ClipboardItem] {
        await withCheckedContinuation { continuation in
            value.withLock { $0.attempts += 1; $0.continuation = continuation }
            started()
        }
    }
    func complete(with items: [ClipboardItem]) {
        let continuation = value.withLock {
            $0.storage = .available
            let continuation = $0.continuation
            $0.continuation = nil
            return continuation
        }
        continuation?.resume(returning: items)
    }
    func flush() { value.withLock { $0.flushes += 1 } }
    func saveItems(_ items: [ClipboardItem]) {}
    func saveImage(_ png: Data, id: UUID) {}
    func loadImage(id: UUID) -> Data? { nil }
    func removeImages(except ids: Set<UUID>) {}
}
