import NotchiumDesignSystem
import SwiftUI

public struct NotchiumShellView: View {
    @Bindable private var model: DynamicIslandPresentationModel
    private let placement: NotchShellPlacement
    private let layout: NotchPanelLayout
    private let renderConfiguration: NotchShellRenderConfiguration

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Namespace private var glassNamespace

    public init(
        model: DynamicIslandPresentationModel,
        placement: NotchShellPlacement,
        layout: NotchPanelLayout,
        renderConfiguration: NotchShellRenderConfiguration = .automatic
    ) {
        self.model = model
        self.placement = placement
        self.layout = layout
        self.renderConfiguration = renderConfiguration
    }

    public var body: some View {
        let accessibility = NotchShellAccessibilityConfiguration.resolve(
            renderConfiguration: renderConfiguration,
            systemReduceMotion: systemReduceMotion,
            systemReduceTransparency: systemReduceTransparency,
            systemIncreaseContrast: colorSchemeContrast == .increased
        )

        GlassEffectContainer(spacing: 8) {
            NotchShellOuterSurface(
                model: model,
                placement: placement,
                layout: layout,
                reduceTransparency: accessibility.reduceTransparency,
                increaseContrast: accessibility.increaseContrast,
                glassNamespace: glassNamespace
            )
        }
        .frame(width: layout.surfaceSize.width, height: layout.surfaceSize.height)
        .preferredColorScheme(renderConfiguration.appearance.colorScheme)
        .animation(shellAnimation(reduceMotion: accessibility.reduceMotion), value: model.visualState)
        .onAppear {
            model.setReduceMotion(accessibility.reduceMotion)
        }
        .onChange(of: accessibility.reduceMotion) { _, value in
            model.setReduceMotion(value)
        }
        .onExitCommand {
            model.collapse()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notchium shell")
        .accessibilityValue(model.phase.accessibilityValue)
        .accessibilityIdentifier("notchium.shell")
    }

    private func shellAnimation(reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .linear(duration: 0.12)
        }
        if model.visualState == .expanded {
            return .spring(duration: 0.30, bounce: 0.12)
        }
        return .easeInOut(duration: 0.18)
    }
}

private struct NotchShellOuterSurface: View {
    @Bindable var model: DynamicIslandPresentationModel
    let placement: NotchShellPlacement
    let layout: NotchPanelLayout
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let glassNamespace: Namespace.ID

    var body: some View {
        ZStack {
            shellContent
            NotchShellStateMarker(state: model.visualState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(
            NotchShellSurfaceModifier(
                cornerRadius: layout.cornerRadius,
                reduceTransparency: reduceTransparency,
                increaseContrast: increaseContrast,
                interactive: model.visualState != .expanded,
                glassNamespace: glassNamespace
            )
        )
        .overlay(alignment: .top) {
            if let bridgeSize = layout.physicalBridgeSize {
                NotchPhysicalBridge(size: bridgeSize)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var shellContent: some View {
        switch model.visualState {
        case .collapsed:
            Button(action: model.toggleExpanded) {
                NotchCollapsedPlaceholder()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand Notchium")
            .accessibilityIdentifier("notchium.shell.toggle")
        case .hovered:
            Button(action: model.toggleExpanded) {
                NotchHoverReveal()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand Notchium")
            .accessibilityIdentifier("notchium.shell.toggle")
        case .expanded:
            NotchExpandedPlaceholderContainer(close: model.collapse)
        }
    }
}

private struct NotchShellStateMarker: View {
    let state: NotchStableState

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Notchium \(state.rawValue)")
            .accessibilityIdentifier("notchium.shell.state.\(state.rawValue)")
    }
}

private struct NotchShellSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let interactive: Bool
    let glassNamespace: Namespace.ID

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if reduceTransparency {
                content
                    .background {
                        shape
                            .fill(.background)
                            .overlay(shape.fill(.regularMaterial).opacity(0.12))
                    }
            } else if interactive {
                content
                    .glassEffect(.regular.interactive(), in: shape)
                    .glassEffectID("notchium-shell-surface", in: glassNamespace)
            } else {
                content
                    .glassEffect(.regular, in: shape)
                    .glassEffectID("notchium-shell-surface", in: glassNamespace)
            }
        }
        .overlay {
            if increaseContrast {
                shape.stroke(.primary.opacity(0.42), lineWidth: 1)
            }
        }
    }
}

private struct NotchPhysicalBridge: View {
    let size: CGSize

    var body: some View {
        UnevenRoundedRectangle(
            bottomLeadingRadius: 8,
            bottomTrailingRadius: 8
        )
        .fill(.black)
        .frame(width: size.width, height: size.height)
    }
}
