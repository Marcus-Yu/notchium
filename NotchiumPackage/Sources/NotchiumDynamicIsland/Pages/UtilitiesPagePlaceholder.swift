import SwiftUI

struct UtilitiesPagePlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("UTILITIES")
                .font(.caption.weight(.semibold))
            Text("Feature arrives in Stage 4")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}
