import NotchiumDesignSystem
import SwiftUI

struct NotchExpandedPlaceholderContainer: View {
    let close: () -> Void

    let pageModel: NotchPageModel

    var body: some View {
        NotchPagesView(model: pageModel)
            .overlay(alignment: .topTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.08), in: .circle)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close Notchium")
                .accessibilityIdentifier("notchium.shell.close")
                .padding(18)
            }
    }
}
