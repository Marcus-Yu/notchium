import Foundation

/// Shared verb-only interface. Clients cannot supply commands, paths, or timeouts.
@objc(NotchiumLidAwakeProtocol)
public protocol LidAwakeProtocol {
    func renew(reply: @escaping @Sendable (Bool, String) -> Void)
    func releaseLease(reply: @escaping @Sendable (Bool, String) -> Void)
}

public enum LidAwakeIdentity {
#if NOTCH_FREE_DISTRIBUTION
    public static let service = "com.marcusyu.notchium.lid-awake-free"
#else
    public static let service = "com.marcusyu.notchium.lid-awake"
#endif
    public static let app = "com.marcusyu.notchium"
    public static let team = "ZU27M973HX"

    /// The code-signing requirement each side places on its peer.
    ///
    /// A Developer ID build pins Apple's anchor and the signing team. The free build is ad-hoc
    /// signed: it has no certificate chain, so only the identifier can be required. The helper then
    /// also accepts only the app that contains it (see its listener), and its interface stays
    /// verb-only, so a spoofing local process can at most hold the keep-awake lease, still bounded
    /// by the 15-second lease, the battery floor and the thermal cutoff. It cannot run anything.
    public static func requirement(identifier: String) -> String {
#if NOTCH_FREE_DISTRIBUTION
        "identifier \"\(identifier)\""
#else
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
#endif
    }
}
