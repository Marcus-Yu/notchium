import NotchiumDesignSystem
import SwiftUI

/// A quiet percentage and charge ring beside the product artwork. The number remains neutral;
/// only the ring carries battery status, with a bolt as a second cue when charging.
struct NotchAirPodsBatteryReadout: View {
    let level: Double
    let charging: Bool
    let reveal: CGFloat
    let reduceMotion: Bool
    @NotchIncreasedContrast private var increaseContrast

    private var charge: Double { min(max(level, 0), 1) }
    private var tone: Tone { Tone(level: charge, charging: charging) }

    var body: some View {
        HStack(spacing: 5) {
            Text("\(Int((charge * 100).rounded()))%")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(increaseContrast ? 1 : 0.9))
                .contentTransition(reduceMotion ? .identity : .numericText())
            Circle()
                .strokeBorder(.white.opacity(increaseContrast ? 0.45 : 0.22), lineWidth: lineWidth)
                .overlay {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: charge * Double(min(max(reveal, 0), 1)))
                        .stroke(tone.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .overlay {
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(tone.color)
                    }
                }
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        }
        .fixedSize()
        .animation(reduceMotion ? nil : NotchMotion.compactLevel, value: level)
        .animation(reduceMotion ? nil : NotchMotion.compactSwap, value: charging)
    }

    private var lineWidth: CGFloat { increaseContrast ? 1.75 : 1.5 }

    enum Tone: Equatable {
        case normal, low

        init(level: Double, charging: Bool) {
            // Match the displayed percentage so a rounded 20% cannot show a healthy ring.
            self = !charging && (min(max(level, 0), 1) * 100).rounded() <= 20 ? .low : .normal
        }

        var color: Color {
            switch self {
            case .normal: .green
            case .low: .red
            }
        }
    }
}
