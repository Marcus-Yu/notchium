import Synchronization

/// Reposted volume events retain this marker, so the single tap always passes them through.
enum VolumeEventReplayGuard {
    static let marker: Int64 = 0x4e6f746368564f4c
    static func isReplay(_ userData: Int64) -> Bool { userData == marker }
}

final class SingleVolumeReplay: Sendable {
    private let claimed = Mutex(false)
    func claim() -> Bool {
        claimed.withLock { if $0 { return false }; $0 = true; return true }
    }
}
