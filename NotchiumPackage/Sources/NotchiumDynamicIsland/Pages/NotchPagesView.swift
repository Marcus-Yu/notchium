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
    var teleprompterRenderer: (any NotchTeleprompterRendering)?
    var clipboardRenderer: (any NotchClipboardRendering)?
    var camera: (any NotchCameraControlling)?
    var cameraPresentationSource = "feature"
    var prepareForReading: @MainActor () -> Void = {}
    var close: () -> Void = {}
    @NotchReducedMotion private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        let cameraOpen = camera?.isPreviewPresented == true
        VStack(spacing: 0) {
            navigation
                .frame(height: ExpandedNotchLayout.navigationHeight)
                // The header blooms first, then the page beneath it, both on the shell spring.
                .notchBloom(stage: 0)
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
                        // Opaque like the shell and explicitly above the page: a removed view
                        // otherwise loses its ZStack order, and the returning page drew through it.
                        .background(.black)
                        .zIndex(1)
                        .transition(reduceMotion ? .opacity : .modifier(active: NotchDownwardReveal(progress: 0),
                                                                        identity: NotchDownwardReveal(progress: 1)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? NotchMotion.reduced : NotchMotion.compactIn, value: cameraOpen)
            .notchBloom(stage: 1)
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
        .onChange(of: pageVisible(.teleprompter), initial: true) { _, visible in
            teleprompterRenderer?.setReadingVisible(visible, source: cameraPresentationSource)
        }
        .onChange(of: isExpanded && cameraOpen, initial: true) { _, visible in
            camera?.setPreviewVisible(visible, source: cameraPresentationSource)
        }
        .onDisappear {
            audioRenderer?.setPageVisible(false)
            shelfRenderer?.setPageVisible(false)
            clipboardRenderer?.setVisible(false)
            pomodoroRenderer?.setPageVisible(false)
            teleprompterRenderer?.setReadingVisible(false, source: cameraPresentationSource)
            camera?.setPreviewVisible(false, source: cameraPresentationSource)
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

    /// Music follows the playing artwork; every other page keeps its fixed identity hue.
    private func hue(for page: NotchPage) -> Color {
        page == .music ? (mediaRenderer?.accentColor ?? page.hue) : page.hue
    }

    /// Every page stays mounted; only the selected one is visible and interactive.
    private var pages: some View {
        ZStack {
            VStack(spacing: 0) {
                if teleprompterRenderer?.meetingSuggested == true {
                    Button { model.selectedPage = .teleprompter } label: {
                        Label("In a meeting? Open Teleprompter", systemImage: "text.alignleft")
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, NotchGeometryResolver.expandedContentHorizontalInset)
                    .padding(.top, 4)
                    .accessibilityIdentifier("notchium.teleprompter.meetingSuggestion")
                }
                HomeDashboardView(pages: model, media: mediaRenderer, calendar: calendarRenderer, quickActions: quickActions)
            }
                .environment(\.notchHomePageVisible, pageVisible(.home))
                .environment(\.notchMediaExpanded, pageVisible(.home))
                .tint(hue(for: .home))
                .modifier(NotchPageVisibility(isVisible: model.selectedPage == .home))
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
            .tint(hue(for: .music))
            .modifier(NotchPageVisibility(isVisible: model.selectedPage == .music))
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
            .tint(hue(for: .calendar))
            .modifier(NotchPageVisibility(isVisible: model.selectedPage == .calendar))
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
            .tint(hue(for: .audio))
            .modifier(NotchPageVisibility(isVisible: model.selectedPage == .audio))
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
            .tint(hue(for: .pomodoro))
            .modifier(NotchPageVisibility(isVisible: model.selectedPage == .pomodoro))
            .disabled(model.selectedPage != .pomodoro)
            .allowsHitTesting(model.selectedPage == .pomodoro)
            .accessibilityElement(children: pageVisible(.pomodoro) ? .contain : .ignore)
            .accessibilityHidden(!pageVisible(.pomodoro))

            Group {
                if let teleprompterRenderer {
                    teleprompterRenderer.expandedTeleprompter(prepareToRead: prepareForReading)
                } else {
                    Text("Teleprompter is unavailable.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .tint(hue(for: .teleprompter))
            .modifier(NotchPageVisibility(isVisible: model.selectedPage == .teleprompter))
            .disabled(model.selectedPage != .teleprompter)
            .allowsHitTesting(model.selectedPage == .teleprompter)
            .accessibilityElement(children: pageVisible(.teleprompter) ? .contain : .ignore)
            .accessibilityHidden(!pageVisible(.teleprompter))

            shelfSection
                .environment(\.notchShelfPageVisible, pageVisible(.shelf) && model.shelfSection == .files)
                .tint(hue(for: .shelf))
                .modifier(NotchPageVisibility(isVisible: model.selectedPage == .shelf))
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
            .modifier(NotchPageVisibility(isVisible: section == .files))
            .disabled(section != .files)
            .allowsHitTesting(section == .files)
            .accessibilityElement(children: section == .files ? .contain : .ignore)
            .accessibilityHidden(section != .files)
            if let clipboardRenderer {
                clipboardRenderer.expandedClipboard()
                    .modifier(NotchPageVisibility(isVisible: section == .clipboard))
                    .disabled(section != .clipboard)
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
                    NotchPageButton(page: page, isSelected: page == model.selectedPage, hue: hue(for: page),
                                    selection: selectionNamespace) {
                        model.selectedPage = page
                    }
                }
            }
            // Every selection source (click, swipe, keys, VoiceOver) slides the same pill.
            .animation(NotchMotionStyle.selection(reduceMotion: reduceMotion), value: model.selectedPage)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Main sections")
            NotchPageSwipeSurface(model: model, isEnabled: isExpanded && !auxiliaryInteractionPresented)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            NotchUtilityControls(caffeine: caffeine, camera: camera, cameraPresentationSource: cameraPresentationSource,
                                 quickReminder: quickActions, close: close)
        }
        .padding(.horizontal, NotchGeometryResolver.expandedContentHorizontalInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notchium header")
    }
}

/// Compact desktop navigation. The selected page shows its own hue on a pill that slides between
/// tabs; selection is also carried by the filled symbol variant and the VoiceOver trait.
private struct NotchPageButton: View {
    let page: NotchPage
    let isSelected: Bool
    let hue: Color
    let selection: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false
    @State private var selectionBounce = 0
    @FocusState private var isFocused: Bool
    @NotchIncreasedContrast private var increaseContrast
    @NotchReducedMotion private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: page.symbol)
                .symbolVariant(isSelected ? .fill : .none)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? hue : .white.opacity(isHovered ? 0.95 : 0.6))
                // The fill variant swaps directly: the sliding pill and the bounce carry the motion,
                // and a replace transition would visibly shrink the tab being left.
                .symbolEffect(.bounce.down, options: .speed(1.6), value: selectionBounce)
                .frame(width: ExpandedPageStyle.headerControlSize, height: ExpandedPageStyle.headerControlSize)
                .background {
                    ZStack {
                        Circle().fill(.white.opacity(isHovered && !isSelected ? NotchPalette.hoverFillOpacity : 0))
                        if isSelected {
                            Circle().fill(hue.opacity(NotchPalette.selectionFillOpacity))
                                .matchedGeometryEffect(id: "notch.page.selection", in: selection)
                        }
                    }
                }
                .overlay {
                    Circle().strokeBorder(isFocused ? .white.opacity(0.95)
                        : (increaseContrast ? (isSelected ? hue : .white.opacity(0.5)) : .clear),
                        lineWidth: isFocused ? 2 : 1)
                }
                .contentShape(.circle)
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .onChange(of: isSelected) { _, selected in
            if selected && !reduceMotion { selectionBounce += 1 }
        }
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
