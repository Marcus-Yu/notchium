public enum DistributionProfile: String, Codable, Equatable, Sendable {
    case developerID
    case appStoreSandboxed
    case freeDirect

    public static var current: Self {
#if NOTCH_APP_STORE
        .appStoreSandboxed
#elseif NOTCH_FREE_DISTRIBUTION
        .freeDirect
#else
        .developerID
#endif
    }
}
