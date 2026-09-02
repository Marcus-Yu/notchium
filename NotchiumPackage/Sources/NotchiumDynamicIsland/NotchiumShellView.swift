import SwiftUI

public struct NotchiumShellView: View {
    @Bindable private var model: DynamicIslandPresentationModel
    private let layout: NotchPanelLayout
    private let renderConfiguration: NotchShellRenderConfiguration

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        model: DynamicIslandPresentationModel,
        layout: NotchPanelLayout,
        renderConfiguration: NotchShellRenderConfiguration = .automatic
    ) {
        self.model = model
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

        ZStack(alignment: .top) {
            Color.clear

            NotchShellOuterSurface(model: model, layout: layout)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.all, edges: .top)
        .overlay {
            if renderConfiguration.showsGeometryOverlay {
                NotchGeometryOverlay(layout: layout)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
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
        return .spring(response: 0.32, dampingFraction: 0.82)
    }
}

private struct NotchShellOuterSurface: View {
    @Bindable var model: DynamicIslandPresentationModel
    let layout: NotchPanelLayout

    var body: some View {
        let shape = NotchShape(
            width: layout.surfaceSize.width,
            height: layout.surfaceSize.height,
            centerX: layout.visibleSurfaceFrame.midX - layout.panelFrame.minX,
            topCornerRadius: layout.topCornerRadius,
            bottomCornerRadius: layout.bottomCornerRadius
        )

        ZStack(alignment: .top) {
            shape.fill(.black)

            shellContent
                .frame(
                    width: layout.surfaceSize.width,
                    height: layout.surfaceSize.height,
                    alignment: .top
                )

            NotchShellStateMarker(state: model.visualState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        .contentShape(shape)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var shellContent: some View {
        switch model.visualState {
        case .collapsed:
            Button(action: model.toggleExpanded) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
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

private struct NotchGeometryOverlay: View {
    let layout: NotchPanelLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(.pink, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))

            geometryOutline(frame: layout.collapsedVisibleFrame, color: .yellow)

            if let hardwareFrame = layout.hardwareNotchGeometry?.frame {
                geometryOutline(frame: hardwareFrame, color: .cyan)
            }
        }
    }

    private func geometryOutline(frame: CGRect, color: Color) -> some View {
        Rectangle()
            .stroke(color, lineWidth: 1)
            .frame(width: frame.width, height: frame.height)
            .offset(
                x: frame.minX - layout.panelFrame.minX,
                y: layout.panelFrame.maxY - frame.maxY
            )
    }
}
