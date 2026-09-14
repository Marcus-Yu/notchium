import SwiftUI

enum NotchMotion {
    // User-specified Stage 4 opening and closing response/damping.
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.80, blendDuration: 0)
    static let close = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    static func morph(opening: Bool) -> Animation { opening ? open : close }

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
                layout: layout
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.all, edges: .top)
        .overlay {
            if renderConfiguration.showsGeometryOverlay, model.surfaceState != .collapsed {
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
    @State private var contentVisible = false

    var body: some View {
        let passiveShape = NotchShape(
            width: layout.collapsedVisibleFrame.width,
            height: layout.collapsedVisibleFrame.height,
            centerX: layout.collapsedVisibleFrame.midX - layout.panelFrame.minX,
            topCornerRadius: 0,
            bottomCornerRadius: layout.hasHardwareNotch ? 8 : 12,
            hardwareExclusion: layout.hardwareNotchGeometry.map {
                CGRect(
                    x: $0.frame.minX - layout.panelFrame.minX,
                    y: 0,
                    width: $0.frame.width,
                    height: $0.frame.height
                )
            }
        )
        let mediaGeometry = CollapsedMediaGeometry(
            hardwareWidth: layout.hardwareNotchGeometry?.frame.width ?? 0,
            hardwareHeight: layout.collapsedVisibleFrame.height
        )
        let shape = NotchShellSurface(
            width: model.showsCollapsedMedia ? mediaGeometry.width : layout.surfaceSize.width,
            height: model.surfaceState == .collapsed ? layout.collapsedVisibleFrame.height : layout.expandedSize.height,
            centerX: layout.visibleSurfaceFrame.midX - layout.panelFrame.minX,
            bottomRadius: model.surfaceState == .collapsed ? passiveShape.bottomCornerRadius : 28,
            passiveShape: passiveShape
        )

        ZStack(alignment: .top) {
            if model.showsCollapsedMedia, let renderer = model.mediaRenderer {
                renderer.collapsedMedia(hardwareWidth: mediaGeometry.hardwareWidth, hardwareHeight: mediaGeometry.height)
                    .frame(width: mediaGeometry.width, height: mediaGeometry.height)
                    .transition(.opacity)
                    .zIndex(2)
            }

            shape.fill(Color.black)
                .zIndex(0)

            shellContent
                .frame(
                    width: layout.expandedSize.width,
                    height: layout.expandedSize.height,
                    alignment: .top
                )
                .zIndex(1)

            NotchShellStateMarker(state: model.surfaceState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlayPreferenceValue(MediaArtworkAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, let renderer = model.mediaRenderer {
                    let rect = proxy[anchor]
                    renderer.mediaArtwork(size: rect.width)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .mask(shape)
        .contentShape(shape)
        .environment(\.notchMediaRenderer, model.mediaRenderer)
        .environment(\.notchSharedMediaArtwork, true)
        .environment(\.notchMediaExpanded, model.surfaceState != .collapsed)
        .foregroundStyle(.white)
    }

    private var shellContent: some View {
        Group {
            Group {
                if model.presentationState == .activity,
                   let activity = model.activityCoordinator.activeActivity {
                    if activity.kind == .media, let renderer = model.mediaRenderer {
                        renderer.expandedMedia()
                    } else {
                        NotchActivityView(activity: activity)
                    }
                } else {
                    NotchExpandedPlaceholderContainer(close: model.collapse, pageModel: model.pageModel)
                }
            }
            .padding(.top, layout.collapsedVisibleFrame.height)
        }
        .opacity(contentVisible ? 1 : 0)
        .blur(radius: contentVisible || model.reduceMotion ? 0 : 3)
        .allowsHitTesting(contentVisible && model.surfaceState != .collapsed)
        .accessibilityHidden(!contentVisible)
        .task(id: model.surfaceState != .collapsed) {
            guard model.surfaceState != .collapsed else {
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
