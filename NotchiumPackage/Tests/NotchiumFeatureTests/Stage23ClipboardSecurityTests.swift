import Foundation
import Observation
import Synchronization
import XCTest
@testable import NotchiumClipboardFeature
import NotchiumServices

final class Stage23ClipboardSecurityTests: XCTestCase {
    func testDiskHistoryDoesNotExposePayloadOrFingerprint() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileClipboardStore(directory: directory, keyStore: TestClipboardKeyStore())
        let text = ClipboardItem(content: .text("stage23-private-clipboard-content"), capturedAt: Date())
        let image = ClipboardItem(content: .image(png: Data("stage23-private-image-bytes".utf8),
                                                  thumbnail: Data("private-thumbnail".utf8),
                                                  pixelSize: .init(width: 1, height: 1)), capturedAt: Date())
        store.saveImage(Data("stage23-private-image-bytes".utf8), id: image.id)
        store.saveItems([text, image])
        store.flush()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let bytes = try files.map { try Data(contentsOf: $0) }.reduce(into: Data()) { $0.append($1) }
        for value in ["stage23-private-clipboard-content", text.fingerprint,
                      "stage23-private-image-bytes", Data("private-thumbnail".utf8).base64EncodedString()] {
            XCTAssertNil(bytes.range(of: Data(value.utf8)), "Clipboard payload and derived metadata must be encrypted")
        }
        XCTAssertEqual(store.loadItems(), [text, image])
        XCTAssertEqual(store.loadImage(id: image.id), Data("stage23-private-image-bytes".utf8))
    }

    func testStoreDirectorySymlinkCannotWriteOutsideManagedDirectory() throws {
        let parent = temporaryDirectory()
        let outside = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = parent.appendingPathComponent("Clipboard")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let store = FileClipboardStore(directory: link, keyStore: TestClipboardKeyStore())
        store.saveItems([ClipboardItem(content: .text("synthetic"), capturedAt: Date())])
        store.flush()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: outside, includingPropertiesForKeys: nil).isEmpty,
                      "Persistence must refuse an app-owned directory replaced by a symbolic link")
    }

    func testLegacyPlaintextHistoryMigratesOnlyAfterEncryptedAssetsAreCommitted() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = ClipboardItem(content: .image(png: Data("legacy-image".utf8), thumbnail: Data("thumb".utf8),
                                                  pixelSize: .init(width: 2, height: 3)), capturedAt: Date())
        let text = ClipboardItem(content: .text("legacy-private-text"), capturedAt: Date())
        try JSONEncoder().encode([text, image]).write(to: directory.appendingPathComponent("history.json"))
        try Data("legacy-image".utf8).write(to: directory.appendingPathComponent("\(image.id.uuidString).png"))

        let store = FileClipboardStore(directory: directory, keyStore: TestClipboardKeyStore())
        XCTAssertEqual(store.loadItems(), [text, image])
        XCTAssertEqual(store.loadImage(id: image.id), Data("legacy-image".utf8))

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(image.id.uuidString).png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.clip").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(image.id.uuidString).clip").path))
    }

    func testIncompleteLegacyMigrationPreservesPlaintextForRecovery() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let item = ClipboardItem(content: .image(png: Data("missing-image".utf8), thumbnail: Data("thumb".utf8),
                                                  pixelSize: .init(width: 1, height: 1)), capturedAt: Date())
        let legacy = try JSONEncoder().encode([item])
        let historyURL = directory.appendingPathComponent("history.json")
        try legacy.write(to: historyURL)

        let store = FileClipboardStore(directory: directory, keyStore: TestClipboardKeyStore())
        XCTAssertTrue(store.loadItems().isEmpty)
        XCTAssertEqual(store.state, .unreadable)
        store.saveItems([])
        store.removeImages(except: [])
        store.flush()

        XCTAssertEqual(try Data(contentsOf: historyURL), legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.clip").path))
    }

    func testMissingKeyForEncryptedHistoryPreservesDataAndBlocksWritesAndCleanup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let seed = FileClipboardStore(directory: directory, keyStore: TestClipboardKeyStore())
        let item = ClipboardItem(content: .text("keep-me"), capturedAt: Date())
        seed.saveItems([item])
        seed.flush()
        let indexURL = directory.appendingPathComponent("history.clip")
        let before = try Data(contentsOf: indexURL)

        let locked = FileClipboardStore(directory: directory, keyStore: MissingClipboardKeyStore())
        XCTAssertTrue(locked.loadItems().isEmpty)
        XCTAssertEqual(locked.state, .locked)
        XCTAssertTrue(ClipboardStorageState.locked.message?.contains("reopen Notchium") == true)
        XCTAssertTrue(ClipboardStorageState.locked.message?.contains("Recent changes may not be saved") == true)
        locked.saveItems([])
        locked.removeImages(except: [])
        locked.flush()

        XCTAssertEqual(try Data(contentsOf: indexURL), before)
    }

    func testCorruptEncryptedHistoryIsUnreadableAndNeverReplacedByEmptyHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent("history.clip")
        let corrupt = Data("not-a-valid-sealed-box".utf8)
        try corrupt.write(to: indexURL)

        let store = FileClipboardStore(directory: directory, keyStore: TestClipboardKeyStore())
        XCTAssertTrue(store.loadItems().isEmpty)
        XCTAssertEqual(store.state, .unreadable)
        store.saveItems([])
        store.removeImages(except: [])
        store.flush()

        XCTAssertEqual(try Data(contentsOf: indexURL), corrupt)
    }

    func testMissingEncryptedImageMarksWholeHistoryUnreadableAndPreventsCleanup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipboardItem(content: .image(png: Data("image".utf8), thumbnail: Data("thumb".utf8),
                                                  pixelSize: .init(width: 1, height: 1)), capturedAt: Date())
        let seed = FileClipboardStore(directory: directory, keyStore: TestClipboardKeyStore())
        seed.saveImage(Data("image".utf8), id: item.id)
        seed.saveItems([item])
        seed.flush()
        let indexURL = directory.appendingPathComponent("history.clip")
        let indexBefore = try Data(contentsOf: indexURL)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("\(item.id.uuidString).clip"))

        let reopened = FileClipboardStore(directory: directory, keyStore: TestClipboardKeyStore())
        XCTAssertTrue(reopened.loadItems().isEmpty)
        XCTAssertEqual(reopened.state, .unreadable)
        reopened.saveItems([])
        reopened.removeImages(except: [])
        reopened.flush()

        XCTAssertEqual(try Data(contentsOf: indexURL), indexBefore)
    }

    @MainActor
    func testAsynchronousStorageFailureUpdatesObservableModelState() async throws {
        let directory = temporaryDirectory()
        let outside = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let store = FileClipboardStore(directory: directory, keyStore: TestClipboardKeyStore())
        let preferencesName = "notchium.stage23.clipboard.state.\(UUID())"
        let preferences = UserDefaults(suiteName: preferencesName)!
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let model = ClipboardModel(service: MockClipboardService(), store: store, preferences: preferences)
        defer { model.stop() }
        store.flush()

        let stateChanged = expectation(description: "observable storage state changes")
        withObservationTracking {
            _ = model.storageState
        } onChange: {
            stateChanged.fulfill()
        }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("history.clip"),
                                                  withDestinationURL: outside.appendingPathComponent("target"))
        model.receive(ClipboardCapture(content: .text("trigger write"), capturedAt: Date()))

        await fulfillment(of: [stateChanged], timeout: 2)
        XCTAssertEqual(model.storageState, .unreadable)
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("notchium-stage23-\(UUID())", isDirectory: true)
    }
}

final class TestClipboardKeyStore: ClipboardEncryptionKeyStoring, Sendable {
    private let value = Mutex<Data?>(Data(repeating: 0x3a, count: 32))
    func read() throws -> Data? { value.withLock { $0 } }
    func create() throws -> Data { value.withLock { data in
        let key = data ?? Data(repeating: 0x3a, count: 32)
        data = key
        return key
    } }
    func remove() { value.withLock { $0 = nil } }
}

private struct MissingClipboardKeyStore: ClipboardEncryptionKeyStoring {
    func read() throws -> Data? { nil }
    func create() throws -> Data { throw ClipboardStorageFailure.keyUnavailable }
}
