import Foundation
import NotchiumCore

@MainActor
public protocol NotchCaffeineControlling: AnyObject {
    var pressInteraction: CaffeinePressInteraction { get }
    var mode: CaffeineMode { get }
    var isBusy: Bool { get }
    var selectedDuration: CaffeineDuration? { get }
    var expiresAt: Date? { get }
    var statusMessage: String? { get }
    var needsClosedLidApproval: Bool { get }
    func cycleMode()
    func keepDisplayAwake()
    func keepAwake(for duration: CaffeineDuration)
    func openClosedLidApproval()
}
