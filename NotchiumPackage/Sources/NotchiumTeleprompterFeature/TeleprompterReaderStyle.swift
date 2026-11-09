import NotchiumDesignSystem
import SwiftUI

enum TeleprompterReaderStyle {
    static let fontRange: ClosedRange<Double> = 16...40
    static let defaultFontSize: Double = 24
    /// The reading marker follows the Teleprompter page hue (`NotchPage.teleprompter.hue`).
    static let marker = NotchPalette.sand

    // Speech updates retarget the current presentation; no timer predicts unread words.
    static let wordFollow = Animation.smooth(duration: 0.24)
    static let lineFollow = Animation.smooth(duration: 0.32)
}
