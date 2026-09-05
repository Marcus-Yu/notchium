import SwiftUI

enum NotchMotion {
    static let morph = Animation.spring(
        response: 0.60,
        dampingFraction: 0.88,
        blendDuration: 0.10
    )

    static let contentIn = Animation.easeOut(duration: 0.18)

    static let contentOut = Animation.easeOut(duration: 0.08)

    static let reduced = Animation.easeInOut(duration: 0.18)
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
                layout: layout,
                accessibility: accessibility
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.all, edges: .top)
        .overlay {
            if renderConfiguration.showsGeometryOverlay, model.visualState != .collapsed {
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
        .accessibilityAction(named: "Toggle Notchium", model.toggleExpanded)
    }
}

private struct NotchShellOuterSurface: View {
    @Bindable var model: DynamicIslandPresentationModel
    let layout: NotchPanelLayout
    let accessibility: NotchShellAccessibilityConfiguration
    @State private var contentVisible = false

    var body: some View {
        let shape = NotchShape(
            width: layout.surfaceSize.width,
            height: layout.surfaceSize.height,
            centerX: layout.visibleSurfaceFrame.midX - layout.panelFrame.minX,
            topCornerRadius: layout.topCornerRadius,
            bottomCornerRadius: layout.bottomCornerRadius,
            hardwareExclusion: layout.hardwareNotchGeometry.map {
                CGRect(
                    x: $0.frame.minX - layout.panelFrame.minX,
                    y: 0,
                    width: $0.frame.width,
                    height: $0.frame.height
                )
            }
        )

        ZStack(alignment: .top) {
            shape.fill(.black)

            shellContent
                .frame(
                    width: layout.expandedSize.width,
                    height: layout.expandedSize.height,
                    alignment: .top
                )

            NotchShellStateMarker(state: model.visualState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        .contentShape(shape)
        .foregroundStyle(.white)
    }

    private var shellContent: some View {
        GlassEffectContainer {
            NotchExpandedPlaceholderContainer(close: model.collapse)
                .padding(.top, layout.collapsedVisibleFrame.height)
                .background {
                    if !accessibility.reduceTransparency {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.clear)
                            .glassEffect(.regular.tint(.black.opacity(0.9)), in: .rect(cornerRadius: 20))
                            .opacity(0.18)
                            .padding(.top, layout.collapsedVisibleFrame.height)
                            .padding(12)
                    }
                }
        }
        .opacity(contentVisible ? 1 : 0)
        .allowsHitTesting(contentVisible && model.visualState != .collapsed)
        .accessibilityHidden(!contentVisible)
        .task(id: model.visualState != .collapsed) {
            guard model.visualState != .collapsed else {
                withAnimation(NotchMotion.contentOut) { contentVisible = false }
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(170))
            } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(NotchMotion.contentIn) { contentVisible = true }
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
