import NotchiumDesignSystem
import SwiftUI

public struct NotchiumShellView: View {
    @Bindable private var model: DynamicIslandPresentationModel
    private let layout: NotchPanelLayout
    private let renderConfiguration: NotchShellRenderConfiguration

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Namespace private var glassNamespace

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

            GlassEffectContainer(spacing: 8) {
                NotchShellOuterSurface(
                    model: model,
                    layout: layout,
                    reduceTransparency: accessibility.reduceTransparency,
                    increaseContrast: accessibility.increaseContrast,
                    glassNamespace: glassNamespace
                )
                .frame(width: layout.surfaceSize.width, height: layout.surfaceSize.height)
            }
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
        if model.visualState == .expanded {
            return .spring(duration: 0.30, bounce: 0.12)
        }
        return .easeInOut(duration: 0.18)
    }
}

private struct NotchShellOuterSurface: View {
    @Bindable var model: DynamicIslandPresentationModel
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
                drawsSoftwareSurface: model.visualState != .collapsed || !layout.hasHardwareNotch,
                isCollapsed: model.visualState == .collapsed,
                reduceTransparency: reduceTransparency,
                increaseContrast: increaseContrast,
                interactive: model.visualState != .expanded,
                glassNamespace: glassNamespace
            )
        )
        .contentShape(NotchShellShape(bottomRadius: layout.cornerRadius))
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

private struct NotchShellSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let drawsSoftwareSurface: Bool
    let isCollapsed: Bool
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let interactive: Bool
    let glassNamespace: Namespace.ID

    func body(content: Content) -> some View {
        let shape = NotchShellShape(bottomRadius: cornerRadius)

        Group {
            if !drawsSoftwareSurface {
                content
            } else if isCollapsed {
                content
                    .background { shape.fill(.black) }
            } else if reduceTransparency {
                content
                    .background {
                        shape
                            .fill(Color(red: 0.025, green: 0.027, blue: 0.032))
                    }
            } else if interactive {
                content
                    .background { shape.fill(.black.opacity(0.92)) }
                    .glassEffect(.regular.tint(.black.opacity(0.78)).interactive(), in: shape)
                    .glassEffectID("notchium-shell-surface", in: glassNamespace)
            } else {
                content
                    .background { shape.fill(.black.opacity(0.92)) }
                    .glassEffect(.regular.tint(.black.opacity(0.78)), in: shape)
                    .glassEffectID("notchium-shell-surface", in: glassNamespace)
            }
        }
        .overlay {
            if !isCollapsed {
                shape.stroke(
                    .white.opacity(increaseContrast ? 0.34 : 0.10),
                    lineWidth: increaseContrast ? 1.25 : 0.75
                )
            }
        }
        .foregroundStyle(.white)
    }
}

private struct NotchShellShape: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
        .path(in: rect)
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
