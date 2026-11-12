import NotchiumDesignSystem
import SwiftUI

enum TeleprompterReaderStyle {
    static let fontRange: ClosedRange<Double> = 16...40
    static let defaultFontSize: Double = 24
    /// The reading marker follows the Teleprompter page hue (`NotchPage.teleprompter.hue`).
    static let marker = NotchPalette.sand

    // Reader motion is a pace-matched glide toward confirmed words (`TeleprompterGlide`);
    // it eases to rest at the latest recognized word and never runs ahead of it.
}
