import SwiftUI

enum NotchMotion {
    // Symmetric, lightly damped motion requested for the black shell only.
    static let shell = Animation.interactiveSpring(response: 0.40, dampingFraction: 0.80, blendDuration: 0)

    static func morph(opening: Bool) -> Animation { shell }
    static func duration(opening: Bool) -> Duration { .milliseconds(400) }

    static let notificationIn = Animation.interactiveSpring(response: 0.26, dampingFraction: 1.0, blendDuration: 0)
    static let notificationOut = Animation.interactiveSpring(response: 0.20, dampingFraction: 1.0, blendDuration: 0)
    static let notificationContent = Animation.easeOut(duration: 0.10)
    static let page = Animation.interactiveSpring(response: 0.20, dampingFraction: 1.0, blendDuration: 0)

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

            // Above the shell: the shell's full-panel content shape would otherwise take its clicks.
            NotchSecondaryActivityChip(model: model, layout: layout)
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
            model.handleEscape()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notchium shell")
        .accessibilityValue(model.phase.accessibilityValue)
        .accessibilityIdentifier("notchium.shell")
        .accessibilityAction(named: "Toggle Notchium", model.toggleExpanded)
        .accessibilityAction(named: "Dismiss notification") {
            model.notificationCoordinator.dismissByUser()
        }
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
        let notification = model.presentedNotification
        let compact = notification?.presentationStyle == .compact
        let compactGeometry = NotchCompactGeometry(layout: layout, activity: notification?.content.compactActivity)
        let notificationSize = NotchNotificationGeometry.size(for: notification?.presentationStyle ?? .feedback, layout: layout)
        let notificationWidth = notificationSize.width
        let notificationHeight = notificationSize.height - layout.collapsedVisibleFrame.height
        let expanded = model.surfaceState != .collapsed
        // The shell's width without any notification: the span a compact activity grows from.
        let baseWidth = expanded ? layout.expandedSize.width
            : (showMedia ? mediaGeometry.width : layout.collapsedVisibleFrame.width)
        let shape = NotchShellSurface(
            width: compact ? compactGeometry.width : (notification != nil ? notificationWidth
                : (expanded ? layout.expandedSize.width + ExpandedShellSilhouette.shoulderRadius * 2 : baseWidth)),
            height: notification != nil ? layout.collapsedVisibleFrame.height + notificationHeight
                : (model.surfaceState == .collapsed ? layout.collapsedVisibleFrame.height : layout.expandedSize.height),
            centerX: model.surfaceState == .collapsed ? passiveShape.centerX : layout.panelFrame.width / 2,
            bottomRadius: compact ? compactGeometry.bottomRadius
                : (notification != nil ? NotchNotificationGeometry.lowerRadius
                   : (model.surfaceState == .collapsed ? passiveShape.bottomCornerRadius : ExpandedShellSilhouette.bottomRadius)),
            passiveShape: passiveShape,
            shoulderRadius: compact ? NotchCompactGeometry.shoulderRadius
                : (notification != nil ? NotchNotificationGeometry.shoulderRadius
                   : (expanded ? ExpandedShellSilhouette.shoulderRadius : 0))
        )

        NotchTransitionSurface(
            expanded: model.surfaceState != .collapsed,
            shape: shape,
            reduceMotion: model.reduceMotion,
            notificationVisible: notification != nil,
            retainsMedia: model.activityCoordinator.retainsMediaPresentation,
            compactVisible: compact,
            compactSpan: NotchCompactSpan(base: baseWidth, full: compactGeometry.width)
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
                                .modifier(CollapsedMediaPresentation(visible: phase == .collapsed && collapsedMediaEligible))
                                .modifier(CompactActivityYield())
                                .allowsHitTesting(showMedia && !compact)
                                .accessibilityHidden(!showMedia || compact)
                        }
                        NotchCompactActivitySlot(model: model, layout: layout)
                    }
                    .frame(height: layout.collapsedVisibleFrame.height)

                    UnifiedNotchNotificationContent(model: model)
                        .frame(width: notificationWidth, height: notification != nil && !compact ? notificationHeight : 0)
                        .modifier(NotchPresentationClip(visible: phase == .collapsed))
                        .allowsHitTesting(model.surfaceState == .collapsed)
                        .accessibilityHidden(model.surfaceState != .collapsed)
                }
                .frame(width: compact ? compactGeometry.width : (notification != nil ? notificationWidth : mediaGeometry.width),
                       alignment: .top)
                .zIndex(3)

                shellContent
                .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
                .modifier(NotchPresentationClip(visible: phase == .expanded))
                .allowsHitTesting(model.surfaceState != .collapsed)
                .accessibilityHidden(model.surfaceState == .collapsed)
                .zIndex(10)

                NotchShellStateMarker(state: model.surfaceState).allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .contentShape(Rectangle())
        .environment(\.notchMediaRenderer, model.mediaRenderer)
        .environment(\.notchSharedMediaArtwork, false)
        .environment(\.notchMediaExpanded, model.surfaceState != .collapsed)
        .foregroundStyle(.white)

    }

    private var shellContent: some View {
        Group {
            ZStack {
                NotchPagesView(model: pageModel,
                               mediaRenderer: model.mediaRenderer,
                               calendarRenderer: model.calendarRenderer,
                               audioRenderer: model.audioRenderer,
                               isExpanded: model.surfaceState != .collapsed,
                               auxiliaryInteractionPresented: model.isAuxiliaryInteractionPresented,
                               caffeine: model.caffeineController,
                               quickActions: model.quickActionsRenderer,
                               close: model.collapse)
                if model.presentationState == .activity,
                   let activity = model.activityCoordinator.activeTransient,
                   activity.kind != .media && activity.kind != .calendar {
                    NotchActivityView(activity: activity)
                }
            }
            .padding(.top, layout.collapsedVisibleFrame.height)
            .overlay(alignment: .bottom) {
                // A successful composer save must remain visible without closing
                // the user's page. Reuse the existing feedback content and slot.
                if model.surfaceState != .collapsed,
                   model.notificationCoordinator.active?.kind == .reminderAdded {
                    UnifiedNotchNotificationContent(model: model, presentedExpanded: true)
                        .frame(height: NotchNotificationGeometry.contentHeight(for: .feedback))
                        .background(.black)
                }
            }
        }
    }
}

/// Alcove-like expanded silhouette: the notch's black flares into the screen edge through
/// concave shoulders (outside the unchanged content width), with continuous lower corners.
enum ExpandedShellSilhouette {
    static let shoulderRadius: CGFloat = 10
    static let bottomRadius: CGFloat = 28
}

/// Collapsed media gives way to a compact activity in step with the shell's reveal.
private struct CompactActivityYield: ViewModifier {
    @Environment(\.notchCompactReveal) private var reveal

    func body(content: Content) -> some View {
        content.opacity(Double(max(0, 1 - reveal * 1.6)))
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
