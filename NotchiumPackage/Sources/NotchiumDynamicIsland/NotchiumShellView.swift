import SwiftUI

enum NotchMotion {
    // Symmetric, lightly damped motion requested for the black shell only.
    static let shell = Animation.interactiveSpring(response: 0.40, dampingFraction: 0.80, blendDuration: 0)

    static func morph(opening: Bool) -> Animation { shell }
    static func duration(opening: Bool) -> Duration { .milliseconds(400) }

    static let reminderResize = Animation.smooth(duration: 0.32)
    static let reminderContentIn = Animation.easeOut(duration: 0.10).delay(0.20)
    static let reminderContentOut = Animation.easeOut(duration: 0.08)

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
        .environment(\.notchAuxiliaryInteraction, model.auxiliaryInteractionHandler)
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
        let collapsedMediaEligible = [.mediaSides, .combined].contains(model.activityCoordinator.presentationMode)
        let showAudioHUD = model.visualState == .collapsed
            && model.activityCoordinator.presentationMode == .compactHUD
            && model.audioHUD != nil
        let reminderWidth = NotchReminderGeometry.width(for: layout)
        let shape = NotchShellSurface(
            width: showAudioHUD ? 292 : (model.surfaceState != .collapsed ? layout.expandedSize.width
                : (showMedia ? mediaGeometry.width : layout.collapsedVisibleFrame.width)),
            height: showAudioHUD ? layout.collapsedVisibleFrame.height + 78
                : (model.surfaceState == .collapsed ? layout.collapsedVisibleFrame.height : layout.expandedSize.height),
            centerX: model.surfaceState == .collapsed ? passiveShape.centerX : layout.panelFrame.width / 2,
            bottomRadius: model.surfaceState == .collapsed ? passiveShape.bottomCornerRadius : 28,
            passiveShape: passiveShape,
            reminderHeight: model.surfaceState == .collapsed ? model.calendarReminderHeight : 0,
            reminderWidth: reminderWidth,
            reminderProgress: model.showsCalendarReminder ? 1 : 0
        )

        NotchTransitionSurface(
            expanded: model.surfaceState != .collapsed,
            shape: shape,
            reduceMotion: model.reduceMotion
        ) { phase in
            ZStack(alignment: .top) {
                // Both rows share the shell's fill and mask. The top row owns the
                // attachment edge, including when there is no media to render.
                VStack(spacing: 0) {
                    ZStack {
                        Color.clear.allowsHitTesting(false)
                        if model.mediaRenderer?.collapsedMediaVisible == true,
                           let renderer = model.mediaRenderer {
                            renderer.collapsedMedia(hardwareWidth: mediaGeometry.hardwareWidth, hardwareHeight: mediaGeometry.height)
                                .frame(width: mediaGeometry.width, height: mediaGeometry.height)
                                .modifier(NotchPresentationClip(visible: phase == .collapsed && collapsedMediaEligible))
                                .allowsHitTesting(showMedia)
                                .accessibilityHidden(!showMedia)
                        }
                    }
                    .frame(height: layout.collapsedVisibleFrame.height)

                    if showAudioHUD, let hud = model.audioHUD {
                        NotchAudioHUDView(
                            hud: hud,
                            action: model.activateCurrentActivity,
                            hoverChanged: model.activityCoordinator.setHovered
                        )
                            .frame(width: 264, height: 74)
                            .padding(.bottom, 4)
                    }

                    if model.showsCalendarReminder, let renderer = model.calendarRenderer {
                        renderer.reminderBanner(action: model.activateCurrentActivity)
                            .frame(width: reminderWidth)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                max(NotchReminderGeometry.minimumHeight, ceil(proxy.size.height))
                            } action: { height in
                                model.calendarReminderHeight = height
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.animation(model.reduceMotion ? NotchMotion.reduced : NotchMotion.reminderContentIn),
                                removal: .opacity.animation(model.reduceMotion ? NotchMotion.reduced : NotchMotion.reminderContentOut)
                            ))
                    }
                }
                .frame(width: showAudioHUD ? 292 : mediaGeometry.width, alignment: .top)
                .zIndex(3)

                ZStack(alignment: .topTrailing) {
                    shellContent
                    NotchUtilityControls(
                        caffeine: model.caffeineController,
                        keyboardLock: model.keyboardLockController,
                        close: model.collapse
                    )
                    .padding(.trailing, NotchGeometryResolver.expandedContentHorizontalInset)
                    .padding(.top, 8)
                }
                .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
                .modifier(NotchPresentationClip(visible: phase == .expanded))
                .allowsHitTesting(model.surfaceState != .collapsed)
                .accessibilityHidden(model.surfaceState == .collapsed)
                .zIndex(10)

                NotchShellStateMarker(state: model.surfaceState).allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .mask(shape)
        }
        .contentShape(Rectangle())
        .environment(\.notchMediaRenderer, model.mediaRenderer)
        .environment(\.notchSharedMediaArtwork, false)
        .environment(\.notchMediaExpanded, model.surfaceState != .collapsed)
        .foregroundStyle(.white)

    }

    private var shellContent: some View {
        Group {
            Group {
                if model.presentationState == .activity,
                   let activity = model.activityCoordinator.activeTransient,
                   activity.kind != .media && activity.kind != .calendar {
                    NotchActivityView(activity: activity)
                } else {
                    NotchPagesView(model: pageModel,
                                   mediaRenderer: model.mediaRenderer,
                                   calendarRenderer: model.calendarRenderer,
                                   audioRenderer: model.audioRenderer,
                                   isExpanded: model.surfaceState != .collapsed)
                }
            }
            .padding(.top, layout.collapsedVisibleFrame.height)
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
