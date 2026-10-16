import Foundation
import Security
import Synchronization
import XCTest
@testable import NotchiumClipboardFeature
import NotchiumServices

final class Stage26ClipboardCompatibilityTests: XCTestCase {
    func testLegacyBackendRecoversEveryKindPinsOrderAndTimestampsWithoutRekeying() throws {
        try withHistory { directory, items, _, key in
            for primary in [nil, Data(repeating: 0x72, count: 32)] {
                let original = try Data(contentsOf: directory.appendingPathComponent("history.clip"))
                let keys = CompatibilityKeys(primary: primary, legacy: key)
                let store = FileClipboardStore(directory: directory, keyStore: keys)
                XCTAssertEqual(store.loadItems(), items)
                XCTAssertEqual(store.state, .available)
                XCTAssertEqual(store.loadImage(id: items[2].id), Data([1, 2, 3]))
                XCTAssertEqual(keys.creations, 0)
                XCTAssertEqual(keys.migrations, primary == nil ? 1 : 0)
                XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("history.clip")), original)
                store.saveItems(items)
                store.flush()
                XCTAssertEqual(store.loadItems(), items, "Later writes continue to use the authenticated original key")
            }
        }
    }

    func testMissingWrongOrDeniedLegacyKeyPreservesAllCiphertext() throws {
        try withHistory { directory, _, original, _ in
            for keys in [CompatibilityKeys(primary: nil, legacy: nil),
                         CompatibilityKeys(primary: nil, legacy: Data(repeating: 0x44, count: 32)),
                         CompatibilityKeys(primary: nil, legacy: nil, failure: .keychain(.readLegacy, errSecAuthFailed)),
                         CompatibilityKeys(primary: nil, legacy: nil, failure: .keychain(.readLegacy, errSecMissingEntitlement))] {
                let store = FileClipboardStore(directory: directory, keyStore: keys)
                XCTAssertTrue(store.loadItems().isEmpty)
                XCTAssertNotEqual(store.state, .available)
                store.saveItems([])
                store.removeImages(except: [])
                store.flush()
                XCTAssertEqual(keys.creations, 0)
                XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("history.clip")), original)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".clip") }.count, 2)
            }
        }
    }

    func testFreshInstallDoesNotProbeLegacyBackendAndVerifiesPrimaryCreation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = CompatibilityKeys(primary: nil, legacy: nil,
                                     failure: .keychain(.readLegacy, errSecMissingEntitlement))
        let store = FileClipboardStore(directory: directory, keyStore: keys)
        XCTAssertTrue(store.loadItems().isEmpty)
        XCTAssertEqual(store.state, .available)
        XCTAssertEqual(keys.creations, 1)
    }

    func testNativeAdapterUsesOneNonStoreIdentityAndReadOnlyLegacyQuery() throws {
        let client = BackendQueryProbe()
        let store = KeychainClipboardEncryptionKeyStore(client: client)
        XCTAssertNil(try store.read())
        XCTAssertNil(try store.readLegacy(allowAuthentication: false))
        XCTAssertEqual(client.backends, [KeychainClipboardEncryptionKeyStore.usesDataProtection,
                                        !KeychainClipboardEncryptionKeyStore.usesDataProtection])
#if !NOTCH_APP_STORE
        XCTAssertFalse(KeychainClipboardEncryptionKeyStore.usesDataProtection,
                       "Debug and free Release must select the same login-Keychain identity")
#endif
    }

    func testOriginalKeyPromotionIsCreateOnlyAndVerifiesTheExactKey() throws {
        let original = Data(repeating: 0x35, count: 32)
        let client = MigrationKeychainProbe(stored: original)
        try KeychainClipboardEncryptionKeyStore(client: client)
            .migrateLegacyKey(original, allowAuthentication: true)
        XCTAssertEqual(client.added, original)
        XCTAssertEqual(client.backend, false)
    }

    func testPromotionNeverOverwritesADifferentConcurrentKey() {
        let client = MigrationKeychainProbe(stored: Data(repeating: 0x67, count: 32), status: errSecDuplicateItem)
        XCTAssertThrowsError(try KeychainClipboardEncryptionKeyStore(client: client)
            .migrateLegacyKey(Data(repeating: 0x35, count: 32), allowAuthentication: false)) { error in
                XCTAssertEqual(error as? ClipboardStorageFailure, .invalidKey)
            }
        XCTAssertEqual(client.stored, Data(repeating: 0x67, count: 32))
    }

    func testAllReferencedImagesMustAuthenticateBeforeKeyPromotion() throws {
        try withHistory { directory, items, original, key in
            let image = directory.appendingPathComponent("\(items[2].id.uuidString).clip")
            let corrupt = Data(repeating: 0x47, count: 64)
            try corrupt.write(to: image)
            let keys = CompatibilityKeys(primary: nil, legacy: key)
            let store = FileClipboardStore(directory: directory, keyStore: keys)
            XCTAssertTrue(store.loadItems().isEmpty)
            XCTAssertNotEqual(store.state, .available)
            XCTAssertEqual(keys.migrations, 0)
            XCTAssertEqual(try Data(contentsOf: image), corrupt)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("history.clip")), original)
        }
    }

    func testPromotionAuthorizationFailurePreservesExistingHistoryAndOriginalKey() throws {
        try withHistory { directory, _, original, key in
            let keys = CompatibilityKeys(primary: nil, legacy: key,
                migrationFailure: .keychain(.migrate, errSecAuthFailed))
            let store = FileClipboardStore(directory: directory, keyStore: keys)
            XCTAssertTrue(store.loadItems().isEmpty)
            XCTAssertEqual(store.state, .keychainFailure(.migrate, errSecAuthFailed))
            store.saveItems([])
            store.removeImages(except: [])
            store.flush()
            XCTAssertEqual(keys.creations, 0)
            XCTAssertEqual(keys.legacy, key)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("history.clip")), original)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".clip") }.count, 2)
        }
    }

    private func withHistory(_ body: (URL, [ClipboardItem], Data, Data) throws -> Void) throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 0x31, count: 32)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var text = ClipboardItem(content: .text("isolated fixture"), capturedAt: date)
        text.isPinned = true
        let items = [text, ClipboardItem(content: .url(URL(string: "https://example.com")!), capturedAt: date),
                     ClipboardItem(content: .image(png: Data([1, 2, 3]), thumbnail: Data([1]), pixelSize: .init(width: 1, height: 1)), capturedAt: date),
                     ClipboardItem(content: .files([URL(fileURLWithPath: "/tmp/fixture.txt")]), capturedAt: date)]
        let seed = FileClipboardStore(directory: directory, keyStore: CompatibilityKeys(primary: key, legacy: nil))
        seed.saveImage(Data([1, 2, 3]), id: items[2].id)
        seed.saveItems(items)
        seed.flush()
        let original = try Data(contentsOf: directory.appendingPathComponent("history.clip"))
        try body(directory, items, original, key)
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("notchium-stage26-\(UUID())")
    }
}

private final class CompatibilityKeys: ClipboardEncryptionKeyStoring, Sendable {
    let primary: Data?
    let legacy: Data?
    let failure: ClipboardStorageFailure?
    let migrationFailure: ClipboardStorageFailure?
    private let count = Mutex(0)
    private let migrationCount = Mutex(0)
    var creations: Int { count.withLock { $0 } }
    var migrations: Int { migrationCount.withLock { $0 } }
    init(primary: Data?, legacy: Data?, failure: ClipboardStorageFailure? = nil,
         migrationFailure: ClipboardStorageFailure? = nil) {
        self.primary = primary; self.legacy = legacy; self.failure = failure
        self.migrationFailure = migrationFailure
    }
    func read() throws -> Data? { primary }
    func readLegacy(allowAuthentication: Bool) throws -> Data? {
        if let failure { throw failure }
        return legacy
    }
    func create() throws -> Data {
        count.withLock { $0 += 1 }
        return Data(repeating: 0x63, count: 32)
    }
    func migrateLegacyKey(_ key: Data, allowAuthentication: Bool) throws {
        migrationCount.withLock { $0 += 1 }
        if let migrationFailure { throw migrationFailure }
    }
}

private final class MigrationKeychainProbe: ClipboardKeychainAccessing, Sendable {
    let stored: Data
    let status: OSStatus
    private let insertion = Mutex<Data?>(nil)
    private let selectedBackend = Mutex<Bool?>(nil)
    var added: Data? { insertion.withLock { $0 } }
    var backend: Bool? { selectedBackend.withLock { $0 } }
    init(stored: Data, status: OSStatus = errSecSuccess) { self.stored = stored; self.status = status }
    func copyMatching(_ query: [String: Any], allowAuthentication: Bool) -> (OSStatus, Data?) {
        (errSecSuccess, stored)
    }
    func add(_ item: [String: Any]) -> OSStatus {
        insertion.withLock { $0 = item[kSecValueData as String] as? Data }
        selectedBackend.withLock { $0 = item[kSecUseDataProtectionKeychain as String] as? Bool }
        return status
    }
}

private final class BackendQueryProbe: ClipboardKeychainAccessing, Sendable {
    private let reads = Mutex<[Bool]>([])
    var backends: [Bool] { reads.withLock { $0 } }
    func copyMatching(_ query: [String: Any], allowAuthentication: Bool) -> (OSStatus, Data?) {
        reads.withLock { $0.append(query[kSecUseDataProtectionKeychain as String] as? Bool ?? false) }
        return (errSecItemNotFound, nil)
    }
    func add(_ item: [String: Any]) -> OSStatus { XCTFail("Compatibility reads must never add a key"); return errSecParam }
}
