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

#if NOTCH_FREE_DISTRIBUTION
    @Test @MainActor func unavailableHelperCannotBeEnabledOrRemoved() async {
        let controller = LidAwakeController()
        let message = controller.message
        #expect(!controller.isAvailableInThisBuild)
        #expect(message.contains("Unavailable in this build"))
        controller.enable()
        controller.setCaffeineActive(true)
        await controller.removeHelper()
        #expect(!controller.isEnabled)
        #expect(!controller.isActive)
        #expect(!controller.needsApproval)
        #expect(controller.message == message)
    }
#endif
}
