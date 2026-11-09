import NotchiumCore
import NotchiumServices
import Testing

struct FreeDistributionTests {
    @Test func compiledProfileMatchesDistributionConfiguration() {
#if NOTCH_APP_STORE
        #expect(DistributionProfile.current == .appStoreSandboxed)
#elseif NOTCH_FREE_DISTRIBUTION
        #expect(DistributionProfile.current == .freeDirect)
#else
        #expect(DistributionProfile.current == .developerID)
#endif
    }

    /// Closed-lid Caffeine ships in both direct builds. The free build is ad-hoc signed, so each
    /// side verifies the other by identifier (the helper additionally by containing bundle); the
    /// Developer ID build keeps the Apple-anchored team requirement.
    @Test @MainActor func closedLidHelperMatchesTheProfileTrustModel() {
        let requirement = LidAwakeIdentity.requirement(identifier: LidAwakeIdentity.app)
#if NOTCH_APP_STORE
        #expect(!LidAwakeController().isAvailableInThisBuild)
#elseif NOTCH_FREE_DISTRIBUTION
        #expect(LidAwakeController().isAvailableInThisBuild)
        #expect(requirement == "identifier \"com.marcusyu.notchium\"")
#else
        #expect(LidAwakeController().isAvailableInThisBuild)
        #expect(requirement.hasPrefix("anchor apple generic"))
        #expect(requirement.contains(LidAwakeIdentity.team))
#endif
        #expect(requirement.contains(LidAwakeIdentity.app))
    }
}
