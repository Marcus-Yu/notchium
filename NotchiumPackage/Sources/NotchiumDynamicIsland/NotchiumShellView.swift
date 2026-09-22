import SwiftUI

enum NotchMotion {
    // Pointer/tap-driven motion is critically damped: responsive, interruptible, and bounce-free.
    static let open = Animation.smooth(duration: 0.34)
    static let close = Animation.smooth(duration: 0.30)

    static func morph(opening: Bool) -> Animation { opening ? open : close }
    static func duration(opening: Bool) -> Duration {
        opening ? .milliseconds(340) : .milliseconds(300)
    }

    static let contentIn = Animation.smooth(duration: 0.22)

    static let contentOut = Animation.smooth(duration: 0.14)

    static let reduced = Animation.easeOut(duration: 0.12)
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
            Color.clear.allowsHitTesting(false)

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
    @ObservedObject private var pageModel: NotchPageModel
    let layout: NotchPanelLayout
    @State private var contentVisible = false

    init(model: DynamicIslandPresentationModel, layout: NotchPanelLayout) {
        self.model = model
        _pageModel = ObservedObject(wrappedValue: model.pageModel)
        self.layout = layout
    }

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
        let showMedia = model.showsCollapsedMedia
        let shape = NotchShellSurface(
            width: showMedia || model.showsCalendarReminder ? mediaGeometry.width
                : layout.surfaceSize.width,
            height: model.surfaceState == .collapsed ? layout.collapsedVisibleFrame.height : layout.expandedSize.height,
            centerX: layout.visibleSurfaceFrame.midX - layout.panelFrame.minX,
            bottomRadius: model.surfaceState == .collapsed ? passiveShape.bottomCornerRadius : 28,
            passiveShape: passiveShape,
            reminderHeight: model.showsCalendarReminder ? NotchReminderGeometry.height : 0
        )

        ZStack(alignment: .top) {
            shape.fill(Color.black)
                .allowsHitTesting(false)
                .zIndex(0)

            // Both rows share the shell's fill and mask. The top row owns the
            // attachment edge, including when there is no media to render.
            VStack(spacing: 0) {
                ZStack {
                    Color.clear.allowsHitTesting(false)
                    if model.mediaRenderer?.collapsedMediaVisible == true,
                       let renderer = model.mediaRenderer {
                        renderer.collapsedMedia(hardwareWidth: mediaGeometry.hardwareWidth, hardwareHeight: mediaGeometry.height)
                            .frame(width: mediaGeometry.width, height: mediaGeometry.height)
                            .opacity(showMedia ? 1 : 0)
                            .allowsHitTesting(showMedia)
                            .accessibilityHidden(!showMedia)
                    }
                }
                .frame(height: layout.collapsedVisibleFrame.height)

                if model.showsCalendarReminder, let renderer = model.calendarRenderer {
                    renderer.reminderBanner()
                        .frame(width: mediaGeometry.width, height: NotchReminderGeometry.height)
                        .transition(.opacity)
                }
            }
            .frame(width: mediaGeometry.width, alignment: .top)
            .zIndex(3)

            shellContent
                .frame(
                    width: layout.expandedSize.width,
                    height: layout.expandedSize.height,
                    alignment: .top
                )
                .zIndex(10)

            if model.surfaceState != .collapsed {
                NotchUtilityControls(close: model.collapse)
                    .padding(.trailing, NotchGeometryResolver.expandedContentHorizontalInset)
                    .padding(.top, 8)
                    .frame(width: layout.expandedSize.width, alignment: .trailing)
                    .zIndex(11)
            }

            NotchShellStateMarker(state: model.surfaceState).allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlayPreferenceValue(MediaArtworkAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if model.showsSharedMediaArtwork,
                   let anchor, let renderer = model.mediaRenderer {
                    let rect = proxy[anchor]
                    renderer.mediaArtwork(size: rect.width)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)
        }
        .mask(shape)
        .contentShape(Rectangle())
        .environment(\.notchMediaRenderer, model.mediaRenderer)
        .environment(\.notchSharedMediaArtwork, true)
        .environment(\.notchMediaExpanded, model.surfaceState != .collapsed)
        .foregroundStyle(.white)
        .animation(model.reduceMotion ? NotchMotion.reduced : .smooth(duration: 0.26),
                   value: model.showsCalendarReminder)
    }

    private var shellContent: some View {
        Group {
            Group {
                if model.presentationState == .activity,
                   let activity = model.activityCoordinator.activeActivity,
                   activity.kind != .media && activity.kind != .calendar {
                    NotchActivityView(activity: activity)
                } else {
                    NotchPagesView(model: pageModel,
                                   mediaRenderer: model.mediaRenderer,
                                   calendarRenderer: model.calendarRenderer)
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
                withAnimation(model.reduceMotion ? NotchMotion.reduced : NotchMotion.contentOut) {
                    contentVisible = false
                }
                return
            }
            withAnimation(model.reduceMotion ? NotchMotion.reduced : NotchMotion.contentIn) {
                contentVisible = true
            }
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
