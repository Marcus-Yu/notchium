import Foundation
import LocalAuthentication
import OSLog
import Security

/// Narrow native boundary, injectable without ever touching a user's Keychain in unit tests.
protocol ClipboardKeychainAccessing: Sendable {
    func copyMatching(_ query: [String: Any], allowAuthentication: Bool) -> (OSStatus, Data?)
    func add(_ item: [String: Any]) -> OSStatus
}

struct SystemClipboardKeychain: ClipboardKeychainAccessing {
    func copyMatching(_ query: [String: Any], allowAuthentication: Bool) -> (OSStatus, Data?) {
        var query = query
        // LAContext suppresses UI for Data Protection. The file-based shim does not
        // reliably honor it; ad-hoc updates can require the system's authorization UI.
        // Do not toggle process-wide interaction settings: Spotify uses Keychain too.
        let context = LAContext()
        context.interactionNotAllowed = !allowAuthentication
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(_ item: [String: Any]) -> OSStatus { SecItemAdd(item as CFDictionary, nil) }
}

/// Only fixed public identifiers, operation, backend and OSStatus. No result/query dumps.
enum ClipboardKeychainDiagnostics {
    static func record(_ operation: ClipboardKeychainOperation, status: OSStatus, dataProtection: Bool) {
        guard status != errSecSuccess else { return }
        let logger = Logger(subsystem: "com.marcusyu.notchium", category: "clipboard-keychain")
        logger.notice("Clipboard Keychain operation=\(operation.rawValue, privacy: .public) OSStatus=\(status, privacy: .public) class=generic-password service=Notchium.Clipboard account=payload-key.v1 dataProtection=\(dataProtection, privacy: .public) synchronizable=false accessGroup=omitted")
    }
}
