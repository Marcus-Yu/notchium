import CryptoKit
import Foundation
import Security

public enum ClipboardStorageState: Equatable, Sendable {
    case available, keyUnavailable, invalidKey, authenticationFailed, corruptHistory, unreadable
    case keychainFailure(ClipboardKeychainOperation, OSStatus)

    public var message: String? {
        let preserved = "Existing history has been preserved. Recent changes may not have been saved."
        switch self {
        case .available: return nil
        case .keyUnavailable:
            return "Clipboard history’s original encryption key couldn’t be found. Restore access to the original Keychain, then try again. History cannot be decrypted without that key. \(preserved)"
        case .invalidKey:
            return "Clipboard history’s stored encryption key is invalid. It has not been replaced. \(preserved)"
        case .authenticationFailed:
            return "Clipboard history failed encryption authentication. The key may not match, or the encrypted data may be damaged. \(preserved)"
        case .corruptHistory:
            return "Clipboard history’s encrypted data is malformed. \(preserved)"
        case .unreadable:
            return "Clipboard history couldn’t be opened safely. \(preserved)"
        case let .keychainFailure(operation, status):
            let reason: String
            switch status {
            case errSecMissingEntitlement:
                reason = "This build isn’t authorized to use the selected Keychain."
            case errSecAuthFailed, errSecUserCanceled:
                reason = "Keychain access was denied or canceled. Try again to authorize access."
            case errSecInteractionNotAllowed, errSecInteractionRequired:
                reason = "The login Keychain is locked or needs authorization. Unlock it, then try again."
            case errSecNotAvailable, errSecInvalidKeychain, errSecNoSuchKeychain:
                reason = "The Keychain is unavailable. Restore access, then try again."
            case errSecItemNotFound:
                reason = "The new encryption key could not be retrieved after storage."
            default:
                reason = "The Keychain operation failed. Try again."
            }
            return "\(reason) (\(operation.rawValue), \(status).) \(preserved)"
        }
    }
}

public enum ClipboardKeychainOperation: String, Equatable, Sendable {
    case read, create, verify
}

enum ClipboardStorageFailure: Error, Equatable {
    case keyUnavailable, invalidKey, keychain(ClipboardKeychainOperation, OSStatus)
    case invalidData, authenticationFailed, corruptHistory, unsafeFile

    var state: ClipboardStorageState {
        switch self {
        case let .keychain(operation, status): .keychainFailure(operation, status)
        case .keyUnavailable: .keyUnavailable
        case .invalidKey: .invalidKey
        case .authenticationFailed: .authenticationFailed
        case .corruptHistory: .corruptHistory
        case .invalidData, .unsafeFile: .unreadable
        }
    }
}

/// The payload key is separate from Spotify credentials and never syncs to another device.
public protocol ClipboardEncryptionKeyStoring: Sendable {
    func read() throws -> Data?
    /// Creates once; on a concurrent creation, returns the existing key instead of replacing it.
    func create() throws -> Data
    func read(allowAuthentication: Bool) throws -> Data?
    func create(allowAuthentication: Bool) throws -> Data
}

public extension ClipboardEncryptionKeyStoring {
    func read(allowAuthentication: Bool) throws -> Data? { try read() }
    func create(allowAuthentication: Bool) throws -> Data { try create() }
}

public struct KeychainClipboardEncryptionKeyStore: ClipboardEncryptionKeyStoring {
    private let client: any ClipboardKeychainAccessing
    public init() { client = SystemClipboardKeychain() }
    init(client: any ClipboardKeychainAccessing) { self.client = client }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Notchium.Clipboard",
         kSecAttrAccount as String: "payload-key.v1",
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: Self.usesDataProtection]
    }

    static var usesDataProtection: Bool {
#if NOTCH_FREE_DISTRIBUTION && !NOTCH_APP_STORE
        false
#else
        true
#endif
    }

    public func read() throws -> Data? { try read(allowAuthentication: false) }
    public func read(allowAuthentication: Bool) throws -> Data? {
        try read(operation: .read, allowAuthentication: allowAuthentication)
    }

    private func read(operation: ClipboardKeychainOperation, allowAuthentication: Bool) throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = client.copyMatching(query, allowAuthentication: allowAuthentication)
        ClipboardKeychainDiagnostics.record(operation, status: status, dataProtection: Self.usesDataProtection)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ClipboardStorageFailure.keychain(operation, status) }
        guard let key = data, key.count == 32 else { throw ClipboardStorageFailure.invalidKey }
        return key
    }

    public func create() throws -> Data { try create(allowAuthentication: false) }
    public func create(allowAuthentication: Bool) throws -> Data {
        if let existing = try read(allowAuthentication: allowAuthentication) { return existing }
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        var item = query
        item[kSecValueData as String] = key
        if Self.usesDataProtection {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        // File-based Keychain items retain the system's default application ACL.
        // Never trust all applications or a requirement based only on a bundle identifier.
        let status = client.add(item)
        ClipboardKeychainDiagnostics.record(.create, status: status, dataProtection: Self.usesDataProtection)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ClipboardStorageFailure.keychain(.create, status)
        }
        guard let stored = try read(operation: .verify, allowAuthentication: allowAuthentication) else {
            throw ClipboardStorageFailure.keychain(.verify, errSecItemNotFound)
        }
        if status == errSecSuccess, stored != key { throw ClipboardStorageFailure.invalidKey }
        return stored
    }
}

enum ClipboardEncryption {
    static func seal(_ data: Data, key: Data, identity: String) throws -> Data {
        guard key.count == 32 else { throw ClipboardStorageFailure.invalidKey }
        let box = try AES.GCM.seal(data, using: SymmetricKey(data: key), authenticating: context(identity))
        guard let combined = box.combined else { throw ClipboardStorageFailure.invalidData }
        return combined
    }

    static func open(_ data: Data, key: Data, identity: String) throws -> Data {
        guard key.count == 32 else { throw ClipboardStorageFailure.invalidKey }
        let box: AES.GCM.SealedBox
        do { box = try AES.GCM.SealedBox(combined: data) }
        catch { throw ClipboardStorageFailure.corruptHistory }
        do { return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: context(identity)) }
        catch CryptoKitError.authenticationFailure { throw ClipboardStorageFailure.authenticationFailed }
    }

    private static func context(_ identity: String) -> Data {
        Data("Notchium.Clipboard.v1:\(identity)".utf8)
    }
}
