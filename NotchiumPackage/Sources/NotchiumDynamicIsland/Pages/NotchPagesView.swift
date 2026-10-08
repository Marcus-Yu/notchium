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
    @NotchReducedMotion private var reduceMotion

    var body: some View {
        let cameraOpen = camera?.isPreviewPresented == true
        VStack(spacing: 0) {
            navigation
                .frame(height: ExpandedNotchLayout.navigationHeight)
                .zIndex(1) // Keep utility hover labels above the page content.

            ZStack {
                pages
                    // The page stays mounted underneath and yields its space to the preview.
                    .opacity(cameraOpen ? 0 : 1)
                    .scaleEffect(cameraOpen && !reduceMotion ? 0.985 : 1, anchor: .top)
                    .allowsHitTesting(!cameraOpen)
                    .accessibilityElement(children: cameraOpen ? .ignore : .contain)
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
        .onChange(of: pageVisible(.audio), initial: true) { _, visible in
            audioRenderer?.setPageVisible(visible)
        }
        .onChange(of: pageVisible(.shelf) && model.shelfSection == .files, initial: true) { _, visible in
            shelfRenderer?.setPageVisible(visible)
        }
        .onChange(of: pageVisible(.shelf) && model.shelfSection == .clipboard,
                  initial: true) { _, visible in
            clipboardRenderer?.setVisible(visible)
        }
        .onChange(of: pageVisible(.pomodoro), initial: true) { _, visible in
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

    private func pageVisible(_ page: NotchPage) -> Bool {
        isExpanded && model.selectedPage == page && camera?.isPreviewPresented != true
    }

    /// Every page stays mounted; only the selected one is visible and interactive.
    private var pages: some View {
        ZStack {
            HomeDashboardView(pages: model, media: mediaRenderer, calendar: calendarRenderer, quickActions: quickActions)
                .environment(\.notchHomePageVisible, pageVisible(.home))
                .environment(\.notchMediaExpanded, pageVisible(.home))
                .opacity(model.selectedPage == .home ? 1 : 0)
                .disabled(model.selectedPage != .home)
                .allowsHitTesting(model.selectedPage == .home)
                .accessibilityElement(children: pageVisible(.home) ? .contain : .ignore)
                .accessibilityHidden(!pageVisible(.home))
            Group {
                if let mediaRenderer {
                    mediaRenderer.expandedMedia()
                } else {
                    MediaPagePlaceholder()
                }
            }
            .environment(\.notchMediaPageVisible, pageVisible(.music))
            .environment(\.notchMediaExpanded, pageVisible(.music))
            .opacity(model.selectedPage == .music ? 1 : 0)
            .disabled(model.selectedPage != .music)
            .allowsHitTesting(model.selectedPage == .music)
            .accessibilityElement(children: pageVisible(.music) ? .contain : .ignore)
            .accessibilityHidden(!pageVisible(.music))

            Group {
                if let calendarRenderer {
                    calendarRenderer.expandedCalendar()
                } else {
                    Text("Calendar is unavailable.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .environment(\.notchCalendarPageVisible, pageVisible(.calendar))
            .opacity(model.selectedPage == .calendar ? 1 : 0)
            .disabled(model.selectedPage != .calendar)
            .allowsHitTesting(model.selectedPage == .calendar)
            .accessibilityElement(children: pageVisible(.calendar) ? .contain : .ignore)
            .accessibilityHidden(!pageVisible(.calendar))

            Group {
                if let audioRenderer {
                    audioRenderer.expandedAudio()
                } else {
                    Text("Audio is unavailable.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .environment(\.notchAudioPageVisible, pageVisible(.audio))
            .opacity(model.selectedPage == .audio ? 1 : 0)
            .disabled(model.selectedPage != .audio)
            .allowsHitTesting(model.selectedPage == .audio)
            .accessibilityElement(children: pageVisible(.audio) ? .contain : .ignore)
            .accessibilityHidden(!pageVisible(.audio))

            Group {
                if let pomodoroRenderer {
                    pomodoroRenderer.expandedPomodoro()
                } else {
                    Text("Focus Timer is unavailable.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .environment(\.notchPomodoroPageVisible, pageVisible(.pomodoro))
            .opacity(model.selectedPage == .pomodoro ? 1 : 0)
            .disabled(model.selectedPage != .pomodoro)
            .allowsHitTesting(model.selectedPage == .pomodoro)
            .accessibilityElement(children: pageVisible(.pomodoro) ? .contain : .ignore)
            .accessibilityHidden(!pageVisible(.pomodoro))

            shelfSection
                .environment(\.notchShelfPageVisible, pageVisible(.shelf) && model.shelfSection == .files)
                .opacity(model.selectedPage == .shelf ? 1 : 0)
                .disabled(model.selectedPage != .shelf)
                .allowsHitTesting(model.selectedPage == .shelf)
                .accessibilityElement(children: pageVisible(.shelf) ? .contain : .ignore)
                .accessibilityHidden(!pageVisible(.shelf))
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
            .accessibilityElement(children: section == .files ? .contain : .ignore)
            .accessibilityHidden(section != .files)
            if let clipboardRenderer {
                clipboardRenderer.expandedClipboard()
                    .opacity(section == .clipboard ? 1 : 0)
                    .allowsHitTesting(section == .clipboard)
                    .accessibilityElement(children: section == .clipboard ? .contain : .ignore)
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
    @FocusState private var isFocused: Bool
    @NotchIncreasedContrast private var increaseContrast

    var body: some View {
        Button(action: action) {
            Image(systemName: page.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(isSelected || isHovered ? 1 : 0.65))
                .frame(width: ExpandedPageStyle.headerControlSize, height: ExpandedPageStyle.headerControlSize)
                .background(.white.opacity(isSelected ? 0.18 : (isHovered ? 0.10 : 0.04)), in: .circle)
                .overlay {
                    Circle().strokeBorder(.white.opacity(isFocused ? 0.95 :
                        (increaseContrast ? (isSelected ? 0.8 : 0.5) : (isSelected ? 0.22 : 0))),
                        lineWidth: isFocused ? 2 : 1)
                }
                .contentShape(.circle)
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .focused($isFocused)
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
