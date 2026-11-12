import Foundation
import Security

/// Shared verb-only interface. Clients cannot supply commands, paths, or timeouts.
@objc(NotchiumLidAwakeProtocol)
public protocol LidAwakeProtocol {
    func renew(reply: @escaping @Sendable (Bool, String) -> Void)
    func releaseLease(reply: @escaping @Sendable (Bool, String) -> Void)
}

public enum LidAwakeIdentity {
    public static let service = "com.marcusyu.notchium.lid-awake"
    public static let app = "com.marcusyu.notchium"
    public static let team = "ZU27M973HX"

    /// The code-signing requirement each side places on its peer.
    ///
    /// A Developer ID build pins Apple's anchor and the signing team. The free build is ad-hoc
    /// signed: it has no certificate chain, so only the identifier can be required here. The free
    /// helper instead requires its client to be the exact app build it was installed with
    /// (`appBuildRequirement`), and its interface stays verb-only, so a spoofing local process can
    /// at most hold the keep-awake lease, still bounded by the 15-second lease, the battery floor
    /// and the thermal cutoff. It cannot run anything.
    public static func requirement(identifier: String) -> String {
#if NOTCH_FREE_DISTRIBUTION
        "identifier \"\(identifier)\""
#else
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
#endif
    }

    /// The free helper's requirement on its client: the app, at exactly the build identified by
    /// `cdhash`. Every copy of one build has the same code-directory hash wherever it is installed
    /// and whichever macOS account runs it; any other binary, including one that reuses the
    /// identifier, has a different hash.
    public static func appBuildRequirement(cdhash: Data) -> String {
        let hex = cdhash.map { String(format: "%02x", $0) }.joined()
        return "identifier \"\(app)\" and cdhash H\"\(hex)\""
    }

    /// The code-directory hash of the bundle (or executable) at `url`, read from its signature on
    /// disk without validating it. Validation happens against the live peer through the
    /// requirement, which the system checks on every message.
    public static func cdhash(of url: URL) -> Data? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let values = information as? [String: Any],
              let hash = values[kSecCodeInfoUnique as String] as? Data, !hash.isEmpty else { return nil }
        return hash
    }
}
