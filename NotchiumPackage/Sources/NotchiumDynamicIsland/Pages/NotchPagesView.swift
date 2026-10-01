import SwiftUI
import NotchiumDesignSystem

/// One selection owns top-level navigation; feature renderers keep their models alive.
struct NotchPagesView: View {
    @ObservedObject var model: NotchPageModel
    let mediaRenderer: (any NotchMediaRendering)?
    let calendarRenderer: (any NotchCalendarRendering)?
    let audioRenderer: (any NotchAudioRendering)?
    let isExpanded: Bool
    var auxiliaryInteractionPresented = false
    var caffeine: (any NotchCaffeineControlling)?
    var quickActions: (any NotchQuickActionsRendering)?
    var shelfRenderer: (any NotchShelfRendering)?
    var pomodoroRenderer: (any NotchPomodoroRendering)?
    var clipboardRenderer: (any NotchClipboardRendering)?
    var camera: (any NotchCameraControlling)?
    var close: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cameraOpen = camera?.isPreviewPresented == true
        VStack(spacing: 0) {
            navigation
                .frame(height: ExpandedNotchLayout.navigationHeight)

            ZStack {
                pages
                    // The page stays mounted underneath and yields its space to the preview.
                    .opacity(cameraOpen ? 0 : 1)
                    .scaleEffect(cameraOpen && !reduceMotion ? 0.985 : 1, anchor: .top)
                    .allowsHitTesting(!cameraOpen)
                    .accessibilityHidden(cameraOpen)
                if cameraOpen, let camera {
                    camera.preview()
                        .transition(reduceMotion ? .opacity : .modifier(active: NotchDownwardReveal(progress: 0),
                                                                        identity: NotchDownwardReveal(progress: 1)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? NotchMotion.reduced : NotchMotion.compactIn, value: cameraOpen)
        }
        .disabled(!isExpanded)
        .onChange(of: isExpanded && model.selectedPage == .audio, initial: true) { _, visible in
            audioRenderer?.setPageVisible(visible)
        }
        .onChange(of: isExpanded && model.selectedPage == .shelf, initial: true) { _, visible in
            shelfRenderer?.setPageVisible(visible)
        }
        .onChange(of: isExpanded && model.selectedPage == .shelf && model.shelfSection == .clipboard,
                  initial: true) { _, visible in
            clipboardRenderer?.setVisible(visible)
        }
        .onChange(of: isExpanded && model.selectedPage == .pomodoro, initial: true) { _, visible in
            pomodoroRenderer?.setPageVisible(visible)
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { camera?.closePreview() }
        }
        .onDisappear {
            audioRenderer?.setPageVisible(false)
            shelfRenderer?.setPageVisible(false)
            clipboardRenderer?.setVisible(false)
            pomodoroRenderer?.setPageVisible(false)
            camera?.closePreview()
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(model.selectedPage.title)
        .accessibilityHint("Use page buttons, or swipe horizontally in the empty space beside them")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.moveSelection(forward: true)
            case .decrement: model.moveSelection(forward: false)
            @unknown default: break
            }
        }
    }

    /// Every page stays mounted; only the selected one is visible and interactive.
    private var pages: some View {
        ZStack {
            HomeDashboardView(pages: model, media: mediaRenderer, calendar: calendarRenderer, quickActions: quickActions)
                .opacity(model.selectedPage == .home ? 1 : 0)
                .disabled(model.selectedPage != .home)
                .allowsHitTesting(model.selectedPage == .home)
                .accessibilityHidden(model.selectedPage != .home)
            Group {
                if let mediaRenderer {
                    mediaRenderer.expandedMedia()
                } else {
                    MediaPagePlaceholder()
                }
            }
            .environment(\.notchMediaPageVisible, model.selectedPage == .music)
            .opacity(model.selectedPage == .music ? 1 : 0)
            .disabled(model.selectedPage != .music)
            .allowsHitTesting(model.selectedPage == .music)
            .accessibilityHidden(model.selectedPage != .music)

            Group {
                if let calendarRenderer {
                    calendarRenderer.expandedCalendar()
                } else {
                    Text("Calendar is unavailable.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .environment(\.notchCalendarPageVisible, model.selectedPage == .calendar)
            .opacity(model.selectedPage == .calendar ? 1 : 0)
            .disabled(model.selectedPage != .calendar)
            .allowsHitTesting(model.selectedPage == .calendar)
            .accessibilityHidden(model.selectedPage != .calendar)

            Group {
                if let audioRenderer {
                    audioRenderer.expandedAudio()
                } else {
                    Text("Audio is unavailable.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .environment(\.notchAudioPageVisible, model.selectedPage == .audio)
            .opacity(model.selectedPage == .audio ? 1 : 0)
            .disabled(model.selectedPage != .audio)
            .allowsHitTesting(model.selectedPage == .audio)
            .accessibilityHidden(model.selectedPage != .audio)

            Group {
                if let pomodoroRenderer {
                    pomodoroRenderer.expandedPomodoro()
                } else {
                    Text("Focus Timer is unavailable.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .environment(\.notchPomodoroPageVisible, isExpanded && model.selectedPage == .pomodoro)
            .opacity(model.selectedPage == .pomodoro ? 1 : 0)
            .disabled(model.selectedPage != .pomodoro)
            .allowsHitTesting(model.selectedPage == .pomodoro)
            .accessibilityHidden(model.selectedPage != .pomodoro)

            shelfSection
                .environment(\.notchShelfPageVisible, model.selectedPage == .shelf)
                .opacity(model.selectedPage == .shelf ? 1 : 0)
                .disabled(model.selectedPage != .shelf)
                .allowsHitTesting(model.selectedPage == .shelf)
                .accessibilityHidden(model.selectedPage != .shelf)
        }
    }

    /// Shelf and, when available, Clipboard share the Shelf page; its title switches between them.
    @ViewBuilder private var shelfSection: some View {
        let section = clipboardRenderer == nil ? .files : model.shelfSection
        let binding: Binding<NotchShelfSection>? = clipboardRenderer == nil ? nil
            : Binding(get: { model.shelfSection }, set: { model.shelfSection = $0 })
        ZStack {
            Group {
                if let shelfRenderer {
                    shelfRenderer.expandedShelf()
                } else {
                    Text("Shelf is unavailable.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .opacity(section == .files ? 1 : 0)
            .allowsHitTesting(section == .files)
            .accessibilityHidden(section != .files)
            if let clipboardRenderer {
                clipboardRenderer.expandedClipboard()
                    .opacity(section == .clipboard ? 1 : 0)
                    .allowsHitTesting(section == .clipboard)
                    .accessibilityHidden(section != .clipboard)
            }
        }
        .environment(\.notchShelfSection, binding)
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            HStack(spacing: ExpandedPageStyle.controlGap) {
                ForEach(model.enabledPages) { page in
                    NotchPageButton(page: page, isSelected: page == model.selectedPage) {
                        model.selectedPage = page
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Main sections")
            NotchPageSwipeSurface(model: model, isEnabled: isExpanded && !auxiliaryInteractionPresented,
                                  reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            NotchUtilityControls(caffeine: caffeine, camera: camera, quickReminder: quickActions, close: close)
        }
        .padding(.horizontal, NotchGeometryResolver.expandedContentHorizontalInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notchium header")
    }
}

/// Compact desktop navigation with selection conveyed by contrast as well as VoiceOver.
private struct NotchPageButton: View {
    let page: NotchPage
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: page.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(isSelected || isHovered ? 1 : 0.65))
                .frame(width: ExpandedPageStyle.headerControlSize, height: ExpandedPageStyle.headerControlSize)
                .background(.white.opacity(isSelected ? 0.18 : (isHovered ? 0.10 : 0.04)), in: .circle)
                .overlay {
                    Circle().strokeBorder(.white.opacity(isSelected ? 0.22 : 0), lineWidth: 1)
                }
                .contentShape(.circle)
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .onHover { isHovered = $0 }
        .help(page.title)
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("notchium.page.\(page.rawValue)")
    }
}

/// The preview grows downward from the header like the notch itself: geometry first, no fade.
nonisolated struct NotchDownwardReveal: ViewModifier, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.mask(alignment: .top) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .frame(height: max(0, proxy.size.height * progress))
            }
        }
    }
}
