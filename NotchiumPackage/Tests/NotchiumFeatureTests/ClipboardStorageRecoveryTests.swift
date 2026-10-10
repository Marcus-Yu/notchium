import Foundation
import Security
import Synchronization
import XCTest
@testable import NotchiumClipboardFeature
import NotchiumServices

final class ClipboardStorageRecoveryTests: XCTestCase {
    func testFailureMatrixPreservesIndexAndImagesWithoutReplacementKeys() throws {
        for failure in [ClipboardStorageFailure.keyUnavailable, .invalidKey,
                        .keychain(.read, errSecAuthFailed), .keychain(.read, errSecNotAvailable),
                        .keychain(.read, errSecInteractionNotAllowed)] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let keys = RecoveringClipboardKeyStore()
            let image = ClipboardItem(content: .image(png: Data([1, 2]), thumbnail: Data([1]),
                                                      pixelSize: .init(width: 1, height: 1)), capturedAt: Date())
            let seed = FileClipboardStore(directory: directory, keyStore: keys)
            seed.saveImage(Data([1, 2]), id: image.id)
            seed.saveItems([image]); seed.flush()
            let index = directory.appendingPathComponent("history.clip")
            let asset = directory.appendingPathComponent("\(image.id).clip")
            let before = try [Data(contentsOf: index), Data(contentsOf: asset)]
            keys.failure = failure
            let reopened = FileClipboardStore(directory: directory, keyStore: keys)
            XCTAssertTrue(reopened.loadItems().isEmpty)
            XCTAssertEqual(reopened.state, failure.state)
            reopened.saveItems([]); reopened.saveImage(Data([9]), id: image.id)
            reopened.removeImages(except: []); reopened.flush()
            XCTAssertEqual(try [Data(contentsOf: index), Data(contentsOf: asset)], before)
            XCTAssertEqual(keys.creations, 0)
            keys.failure = nil
            XCTAssertEqual(reopened.loadItems(), [image])
        }
    }

    func testInvalidKeyLengthAndAuthenticatedCiphertextFailureAreDistinct() throws {
        XCTAssertThrowsError(try ClipboardEncryption.open(Data(repeating: 1, count: 64),
                                                          key: Data(repeating: 1, count: 31), identity: "history")) {
            XCTAssertEqual($0 as? ClipboardStorageFailure, .invalidKey)
        }
        let sealed = try ClipboardEncryption.seal(Data("synthetic".utf8), key: Data(repeating: 1, count: 32),
                                                  identity: "history")
        XCTAssertThrowsError(try ClipboardEncryption.open(sealed, key: Data(repeating: 2, count: 32), identity: "history")) {
            XCTAssertEqual($0 as? ClipboardStorageFailure, .authenticationFailed)
        }
    }

    func testInterruptedMigrationWithOrphanCiphertextDoesNotGenerateANewKey() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = Data("original legacy recovery evidence".utf8)
        let orphan = Data("interrupted ciphertext".utf8)
        let legacyURL = directory.appendingPathComponent("history.json")
        let orphanURL = directory.appendingPathComponent("\(UUID()).clip")
        try legacy.write(to: legacyURL); try orphan.write(to: orphanURL)
        let keys = MissingCountingClipboardKeyStore()
        let store = FileClipboardStore(directory: directory, keyStore: keys)
        XCTAssertTrue(store.loadItems().isEmpty)
        XCTAssertEqual(store.state, .keyUnavailable)
        store.saveItems([]); store.removeImages(except: []); store.flush()
        XCTAssertEqual(keys.creations, 0)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacy)
        XCTAssertEqual(try Data(contentsOf: orphanURL), orphan)
    }

    func testEntitlementFailureIsNotReportedAsLockedAndPreservesHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = RecoveringClipboardKeyStore()
        let seed = FileClipboardStore(directory: directory, keyStore: keys)
        seed.saveItems([ClipboardItem(content: .text("saved history"), capturedAt: Date())])
        seed.flush()
        let index = directory.appendingPathComponent("history.clip")
        let original = try Data(contentsOf: index)
        keys.failure = .keychain(.read, errSecMissingEntitlement)

        let store = FileClipboardStore(directory: directory, keyStore: keys)
        XCTAssertTrue(store.loadItems().isEmpty)
        XCTAssertEqual(store.state, .keychainFailure(.read, errSecMissingEntitlement))
        store.saveItems([])
        store.removeImages(except: [])
        store.flush()
        XCTAssertEqual(try Data(contentsOf: index), original)
        XCTAssertEqual(keys.creations, 0, "Never replace the key for existing ciphertext")
    }

    @MainActor
    func testOpeningClipboardAfterUnlockRestoresCommittedHistoryBeforeCapture() async throws {
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
        keys.failure = .keychain(.read, errSecInteractionNotAllowed)
        let suite = "notchium.clipboard.recovery.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = ClipboardModel(service: MockClipboardService(), store: store, preferences: preferences)
        defer { model.stop() }
        await waitForStorage(model)
        XCTAssertEqual(model.storageState, .keychainFailure(.read, errSecInteractionNotAllowed))
        model.receive(ClipboardCapture(content: .text("while unavailable"), capturedAt: Date()))
        XCTAssertTrue(model.items.isEmpty, "Unavailable history must not accumulate a conflicting in-memory history")

        keys.failure = nil
        model.setVisible(true)
        await waitForStorage(model)
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
    func testFailedRetryKeepsHistoryUntouchedThenExplicitRetryRecovers() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = RecoveringClipboardKeyStore()
        let store = FileClipboardStore(directory: directory, keyStore: keys)
        let saved = ClipboardItem(content: .text("saved"), capturedAt: Date())
        store.saveItems([saved])
        store.flush()
        let original = try Data(contentsOf: directory.appendingPathComponent("history.clip"))
        keys.failure = .keychain(.read, errSecInteractionNotAllowed)
        let suite = "notchium.clipboard.retry.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = ClipboardModel(service: MockClipboardService(), store: store, preferences: preferences)
        defer { model.stop() }
        await waitForStorage(model)

        model.retryStorage()
        await waitForStorage(model)
        model.clear(includingPinned: true)
        store.flush()
        XCTAssertEqual(model.storageState, .keychainFailure(.read, errSecInteractionNotAllowed))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("history.clip")), original)

        keys.failure = nil
        model.retryStorage()
        await waitForStorage(model)
        XCTAssertEqual(model.storageState, .available)
        XCTAssertEqual(model.items, [saved])
    }

    @MainActor
    private func waitForStorage(_ model: ClipboardModel) async {
        while model.isLoadingStorage { await Task.yield() }
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("notchium-clipboard-recovery-\(UUID())", isDirectory: true)
    }
}

private final class MissingCountingClipboardKeyStore: ClipboardEncryptionKeyStoring, Sendable {
    private let count = Mutex(0)
    var creations: Int { count.withLock { $0 } }
    func read() throws -> Data? { nil }
    func create() throws -> Data {
        count.withLock { $0 += 1 }
        return Data(repeating: 1, count: 32)
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
