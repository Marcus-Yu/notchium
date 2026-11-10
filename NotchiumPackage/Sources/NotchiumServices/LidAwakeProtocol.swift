import Foundation

/// Shared verb-only interface. Clients cannot supply commands, paths, or timeouts.
@objc(NotchiumLidAwakeProtocol)
public protocol LidAwakeProtocol {
    func renew(reply: @escaping @Sendable (Bool, String) -> Void)
    func releaseLease(reply: @escaping @Sendable (Bool, String) -> Void)
}

public enum LidAwakeIdentity {
#if NOTCH_FREE_DISTRIBUTION
    public static let service = "com.marcusyu.notchium.lid-awake-free-v2"
#else
    public static let service = "com.marcusyu.notchium.lid-awake"
#endif
    public static let app = "com.marcusyu.notchium"
    public static let team = "ZU27M973HX"

    /// The code-signing requirement each side places on its peer.
    ///
    /// A Developer ID build pins Apple's anchor and the signing team. The free build is ad-hoc
    /// signed: it has no certificate chain, so the app checks the daemon's launchd identity.
    /// The daemon adds the registered app's code hash before accepting an XPC client.
    /// Both profiles expose only the bounded keep-awake lease.
    public static func requirement(identifier: String) -> String {
#if NOTCH_FREE_DISTRIBUTION
        "identifier \"\(identifier)\""
#else
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
#endif
    }
}
