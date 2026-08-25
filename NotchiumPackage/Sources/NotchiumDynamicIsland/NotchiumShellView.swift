import NotchiumDesignSystem
import SwiftUI

public struct NotchiumShellView: View {
    @Bindable private var model: DynamicIslandPresentationModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: DynamicIslandPresentationModel) {
        self.model = model
    }

    public var body: some View {
        Button {
            model.toggleOpened()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "capsule.fill")
                    .imageScale(.small)

                if model.interaction != .collapsed {
                    Text("Notchium")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .foregroundStyle(.white)
            .frame(
                minWidth: NotchiumDesignMetrics.minimumHitTarget,
                minHeight: NotchiumDesignMetrics.minimumHitTarget
            )
            .padding(.horizontal, model.interaction == .collapsed ? 4 : 12)
            .background(.black, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover(perform: model.setHovered)
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.22),
            value: model.interaction
        )
        .accessibilityLabel("Open Notchium")
        .accessibilityValue(model.interaction.rawValue)
    }
}
