import NotchiumDesignSystem
import SwiftUI

struct NotchHoverReveal: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 24, weight: .medium))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Notchium is ready")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Text("Click to open")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.56))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

struct NotchExpandedPlaceholderContainer: View {
    let close: () -> Void

    var body: some View {
        VStack(spacing: NotchiumDesignMetrics.standardSpacing) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notchium")
                        .font(.headline)
                    Text("Shell preview")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer()

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.black.opacity(0.48)).interactive(), in: .circle)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close Notchium")
                .accessibilityIdentifier("notchium.shell.close")
            }

            HStack(spacing: NotchiumDesignMetrics.standardSpacing) {
                placeholderCard(title: "Primary", symbol: "circle.grid.2x2")
                placeholderCard(title: "Context", symbol: "sparkles")
            }

            placeholderCard(title: "Future activity surface", symbol: "rectangle.3.group")
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholderCard(title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.white.opacity(0.58))
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
