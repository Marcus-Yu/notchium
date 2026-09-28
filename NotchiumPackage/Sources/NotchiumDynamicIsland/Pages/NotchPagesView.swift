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
    var close: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            navigation
                .frame(height: ExpandedNotchLayout.navigationHeight)

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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(!isExpanded)
        .onChange(of: isExpanded && model.selectedPage == .audio, initial: true) { _, visible in
            audioRenderer?.setPageVisible(visible)
        }
        .onDisappear { audioRenderer?.setPageVisible(false) }
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
            NotchUtilityControls(caffeine: caffeine, quickReminder: quickActions, close: close)
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
