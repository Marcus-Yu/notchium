public enum DistributionProfile: String, Codable, Equatable, Sendable {
    case developerID
    case appStoreSandboxed

    public static var current: Self {
#if NOTCH_APP_STORE
        .appStoreSandboxed
#else
        .developerID
#endif
    }
}
