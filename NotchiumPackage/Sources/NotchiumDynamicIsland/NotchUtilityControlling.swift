import Foundation
import NotchiumCore

@MainActor
public protocol NotchCaffeineControlling: AnyObject {
    var mode: CaffeineMode { get }
    var isBusy: Bool { get }
    func cycleMode()
    func keepDisplayAwake()
}
