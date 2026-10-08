import CryptoKit
import Foundation
import LocalAuthentication
import Security

public enum ClipboardStorageState: Equatable, Sendable {
    case available, locked, keyUnavailable, unreadable

    public var message: String? {
        switch self {
        case .available: nil
        case .locked: "Clipboard history’s encryption key is locked. Unlock your Mac, then try again. Recent changes may not have been saved."
        case .keyUnavailable: "Clipboard history’s encryption key isn’t available. Try again. Existing history has been preserved. Recent changes may not have been saved."
        case .unreadable: "Clipboard history couldn’t be opened safely. Existing data has been preserved."
        }
    }
}

enum ClipboardStorageFailure: Error, Equatable {
    case keyUnavailable, keychain(OSStatus), invalidData, unsafeFile

    var state: ClipboardStorageState {
        switch self {
        case .keychain(errSecInteractionNotAllowed): .locked
        case .keyUnavailable, .keychain: .keyUnavailable
        case .invalidData, .unsafeFile: .unreadable
        }
    }
}

/// The payload key is separate from Spotify credentials and never syncs to another device.
public protocol ClipboardEncryptionKeyStoring: Sendable {
    func read() throws -> Data?
    /// Creates once; on a concurrent creation, returns the existing key instead of replacing it.
    func create() throws -> Data
}

public struct KeychainClipboardEncryptionKeyStore: ClipboardEncryptionKeyStoring {
    public init() {}
    private var query: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Notchium.Clipboard",
         kSecAttrAccount as String: "payload-key.v1",
         kSecAttrSynchronizable as String: false]
#if !NOTCH_FREE_DISTRIBUTION || NOTCH_APP_STORE
        // Data Protection Keychain requires a provisioned access group. Free
        // builds use the local login Keychain; payload encryption is unchanged.
        query[kSecUseDataProtectionKeychain as String] = true
#endif
        return query
    }

    public func read() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Background observation must never present a Keychain authentication dialog.
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ClipboardStorageFailure.keychain(status) }
        guard let key = result as? Data, key.count == 32 else {
            throw ClipboardStorageFailure.keyUnavailable
        }
        return key
    }

    public func create() throws -> Data {
        if let existing = try read() { return existing }
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        var item = query
        item[kSecValueData as String] = key
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try read() { return existing }
        guard status == errSecSuccess else { throw ClipboardStorageFailure.keychain(status) }
        return key
    }
}

enum ClipboardEncryption {
    static func seal(_ data: Data, key: Data, identity: String) throws -> Data {
        guard key.count == 32 else { throw ClipboardStorageFailure.keyUnavailable }
        let box = try AES.GCM.seal(data, using: SymmetricKey(data: key), authenticating: context(identity))
        guard let combined = box.combined else { throw ClipboardStorageFailure.invalidData }
        return combined
    }

    static func open(_ data: Data, key: Data, identity: String) throws -> Data {
        guard key.count == 32 else { throw ClipboardStorageFailure.keyUnavailable }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: key),
                                authenticating: context(identity))
    }

    private static func context(_ identity: String) -> Data {
        Data("Notchium.Clipboard.v1:\(identity)".utf8)
    }
}
