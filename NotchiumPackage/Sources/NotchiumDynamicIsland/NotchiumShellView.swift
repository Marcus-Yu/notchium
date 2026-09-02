import SwiftUI

enum NotchMotion {
    static let notchMorphAnimation: Animation =
        .spring(
            response: 0.62,
            dampingFraction: 0.90,
            blendDuration: 0.12
        )
    static let reducedMotionAnimation = Animation.easeInOut(duration: 0.18)

    static func shellStateAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedMotionAnimation : notchMorphAnimation
    }

    static let contentInsertion = Animation
        .easeOut(duration: 0.22)
        .delay(0.16)
    static let contentRemoval = Animation.easeOut(duration: 0.22)
}

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

            NotchShellOuterSurface(
                model: model,
                layout: layout
            )
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
            .transition(contentTransition)
        case .expanded:
            NotchExpandedPlaceholderContainer(close: model.collapse)
                .transition(contentTransition)
        }
    }

    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(NotchMotion.contentInsertion),
            removal: .opacity.animation(NotchMotion.contentRemoval)
        )
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
