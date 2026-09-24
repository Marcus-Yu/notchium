import Foundation

/// Shared verb-only interface. Clients cannot supply commands, paths, or timeouts.
@objc(NotchiumLidAwakeProtocol)
public protocol LidAwakeProtocol {
    func renew(reply: @escaping @Sendable (Bool, String) -> Void)
    func releaseLease(reply: @escaping @Sendable (Bool, String) -> Void)
}

public enum LidAwakeIdentity {
    public static let service = "com.marcusyu.notchium.lid-awake"
    public static let team = "ZU27M973HX"
    public static func requirement(identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}
