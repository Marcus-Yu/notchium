import Foundation
import Security
import Synchronization
import XCTest
@testable import NotchiumClipboardFeature
import NotchiumServices

final class ClipboardStorageRecoveryTests: XCTestCase {
    func testEntitlementFailureIsNotReportedAsLockedAndPreservesHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = RecoveringClipboardKeyStore()
        let seed = FileClipboardStore(directory: directory, keyStore: keys)
        seed.saveItems([ClipboardItem(content: .text("saved history"), capturedAt: Date())])
        seed.flush()
        let index = directory.appendingPathComponent("history.clip")
        let original = try Data(contentsOf: index)
        keys.failure = .keychain(errSecMissingEntitlement)

        let store = FileClipboardStore(directory: directory, keyStore: keys)
        XCTAssertTrue(store.loadItems().isEmpty)
        XCTAssertEqual(store.state, .keyUnavailable)
        store.saveItems([])
        store.removeImages(except: [])
        store.flush()
        XCTAssertEqual(try Data(contentsOf: index), original)
        XCTAssertEqual(keys.creations, 0, "Never replace the key for existing ciphertext")
    }

    @MainActor
    func testOpeningClipboardAfterUnlockRestoresCommittedHistoryBeforeCapture() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = RecoveringClipboardKeyStore()
        let store = FileClipboardStore(directory: directory, keyStore: keys)
        var pinned = ClipboardItem(content: .text("pinned"), capturedAt: Date())
        pinned.isPinned = true
        let image = ClipboardItem(content: .image(png: Data([1, 2]), thumbnail: Data([1]),
                                                  pixelSize: .init(width: 1, height: 1)), capturedAt: Date())
        store.saveImage(Data([1, 2]), id: image.id)
        store.saveItems([pinned, image])
        store.flush()
        keys.failure = .keychain(errSecInteractionNotAllowed)
        let suite = "notchium.clipboard.recovery.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = ClipboardModel(service: MockClipboardService(), store: store, preferences: preferences)
        defer { model.stop() }
        XCTAssertEqual(model.storageState, .locked)
        model.receive(ClipboardCapture(content: .text("while unavailable"), capturedAt: Date()))
        XCTAssertTrue(model.items.isEmpty, "Unavailable history must not accumulate a conflicting in-memory history")

        keys.failure = nil
        model.setVisible(true)
        XCTAssertEqual(model.storageState, .available)
        XCTAssertEqual(model.items, [pinned, image])
        XCTAssertEqual(store.loadImage(id: image.id), Data([1, 2]))
        model.receive(ClipboardCapture(content: .text("after unlock"), capturedAt: Date()))
        store.flush()
        XCTAssertEqual(store.loadItems().map(\.preview), ["after unlock", "pinned", "Image · 1 × 1"])
        XCTAssertTrue(store.loadItems()[1].isPinned)
        XCTAssertEqual(keys.creations, 0)
    }

    @MainActor
    func testFailedRetryKeepsHistoryUntouchedThenExplicitRetryRecovers() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = RecoveringClipboardKeyStore()
        let store = FileClipboardStore(directory: directory, keyStore: keys)
        let saved = ClipboardItem(content: .text("saved"), capturedAt: Date())
        store.saveItems([saved])
        store.flush()
        let original = try Data(contentsOf: directory.appendingPathComponent("history.clip"))
        keys.failure = .keychain(errSecInteractionNotAllowed)
        let suite = "notchium.clipboard.retry.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = ClipboardModel(service: MockClipboardService(), store: store, preferences: preferences)
        defer { model.stop() }

        model.retryStorage()
        model.clear(includingPinned: true)
        store.flush()
        XCTAssertEqual(model.storageState, .locked)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("history.clip")), original)

        keys.failure = nil
        model.retryStorage()
        XCTAssertEqual(model.storageState, .available)
        XCTAssertEqual(model.items, [saved])
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("notchium-clipboard-recovery-\(UUID())", isDirectory: true)
    }
}

private final class RecoveringClipboardKeyStore: ClipboardEncryptionKeyStoring, Sendable {
    private let value = Mutex((failure: ClipboardStorageFailure?.none, creations: 0))
    var failure: ClipboardStorageFailure? {
        get { value.withLock { $0.failure } }
        set { value.withLock { $0.failure = newValue } }
    }
    var creations: Int { value.withLock { $0.creations } }
    func read() throws -> Data? {
        if let failure { throw failure }
        return Data(repeating: 0x3a, count: 32)
    }
    func create() throws -> Data {
        value.withLock { $0.creations += 1 }
        return try read()!
    }
}
