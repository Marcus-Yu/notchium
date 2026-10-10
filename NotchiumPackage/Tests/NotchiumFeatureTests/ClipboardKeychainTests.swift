import Foundation
import Security
import Synchronization
import XCTest
@testable import NotchiumClipboardFeature

final class ClipboardKeychainTests: XCTestCase {
    func testOnlyItemNotFoundMeansMissingKey() throws {
        for status in [errSecMissingEntitlement, errSecAuthFailed, errSecInteractionNotAllowed,
                       errSecInteractionRequired, errSecNotAvailable, errSecUserCanceled] {
            let store = KeychainClipboardEncryptionKeyStore(client: ScriptedClipboardKeychain(reads: [(status, nil)]))
            XCTAssertThrowsError(try store.read()) { error in
                XCTAssertEqual(error as? ClipboardStorageFailure, .keychain(.read, status))
            }
        }
        XCTAssertNil(try KeychainClipboardEncryptionKeyStore(
            client: ScriptedClipboardKeychain(reads: [(errSecItemNotFound, nil)])).read())
    }

    func testInvalidKeyMaterialIsDistinctFromMissingKey() {
        for data in [Data(), Data(repeating: 1, count: 31), Data(repeating: 1, count: 33)] {
            let store = KeychainClipboardEncryptionKeyStore(client: ScriptedClipboardKeychain(reads: [(errSecSuccess, data)]))
            XCTAssertThrowsError(try store.read()) { error in
                XCTAssertEqual(error as? ClipboardStorageFailure, .invalidKey)
            }
        }
    }

    func testCreationMustVerifyStoredKeyBeforeHistoryCanBeEncrypted() {
        let client = ScriptedClipboardKeychain(reads: [(errSecItemNotFound, nil), (errSecNotAvailable, nil)])
        let store = KeychainClipboardEncryptionKeyStore(client: client)
        XCTAssertThrowsError(try store.create()) { error in
            XCTAssertEqual(error as? ClipboardStorageFailure, .keychain(.verify, errSecNotAvailable))
        }
        XCTAssertEqual(client.adds, 1)
    }

    func testConcurrentCreationReadsWinnerWithoutReplacingIt() throws {
        let winner = Data(repeating: 0x35, count: 32)
        let client = ScriptedClipboardKeychain(reads: [(errSecItemNotFound, nil), (errSecSuccess, winner)],
                                              addStatus: errSecDuplicateItem)
        XCTAssertEqual(try KeychainClipboardEncryptionKeyStore(client: client).create(), winner)
        XCTAssertEqual(client.adds, 1)
    }

    func testSuccessfulAddWithDifferentReadbackKeyFailsClosed() {
        let client = ScriptedClipboardKeychain(reads: [(errSecItemNotFound, nil),
                                                      (errSecSuccess, Data(repeating: 0x35, count: 32))])
        XCTAssertThrowsError(try KeychainClipboardEncryptionKeyStore(client: client).create()) { error in
            XCTAssertEqual(error as? ClipboardStorageFailure, .invalidKey)
        }
    }
}

private final class ScriptedClipboardKeychain: ClipboardKeychainAccessing, Sendable {
    private let value: Mutex<(reads: [(OSStatus, Data?)], adds: Int)>
    private let addStatus: OSStatus
    init(reads: [(OSStatus, Data?)], addStatus: OSStatus = errSecSuccess) {
        value = Mutex((reads, 0)); self.addStatus = addStatus
    }
    var adds: Int { value.withLock { $0.adds } }
    func copyMatching(_ query: [String: Any], allowAuthentication: Bool) -> (OSStatus, Data?) {
        value.withLock { $0.reads.removeFirst() }
    }
    func add(_ item: [String: Any]) -> OSStatus {
        value.withLock { $0.adds += 1 }; return addStatus
    }
}
