import Foundation
import NotchiumCore

@MainActor
public protocol NotchCaffeineControlling: AnyObject {
    var pressInteraction: CaffeinePressInteraction { get }
    var mode: CaffeineMode { get }
    var isBusy: Bool { get }
    func cycleMode()
    func keepDisplayAwake()
}
