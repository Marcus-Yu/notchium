import SwiftUI

/// One selection owns top-level navigation; feature renderers keep their models alive.
struct NotchPagesView: View {
    @ObservedObject var model: NotchPageModel
    let mediaRenderer: (any NotchMediaRendering)?
    let calendarRenderer: (any NotchCalendarRendering)?
    let audioRenderer: (any NotchAudioRendering)?
    let isExpanded: Bool
    var auxiliaryInteractionPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func pageOffset(_ page: NotchPage) -> CGFloat {
        guard !reduceMotion, page != model.selectedPage,
              let pageIndex = model.enabledPages.firstIndex(of: page),
              let selectedIndex = model.enabledPages.firstIndex(of: model.selectedPage) else { return 0 }
        return pageIndex < selectedIndex ? -4 : 4
    }

    var body: some View {
        VStack(spacing: 0) {
            navigation
                .frame(height: ExpandedNotchLayout.navigationHeight)

            ZStack {
                HomeDashboardView(pages: model, media: mediaRenderer, calendar: calendarRenderer)
                    .opacity(model.selectedPage == .home ? 1 : 0)
                    .offset(x: pageOffset(.home))
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
                .offset(x: pageOffset(.music))
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
                .offset(x: pageOffset(.calendar))
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
                .offset(x: pageOffset(.audio))
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
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(model.enabledPages) { page in
                        Button {
                            model.selectedPage = page
                        } label: {
                            Label(page.title, systemImage: page.symbol)
                                .font(.system(size: 11, weight: page == model.selectedPage ? .semibold : .medium))
                                .foregroundStyle(.white.opacity(page == model.selectedPage ? 1 : 0.58))
                                .padding(.horizontal, 10)
                                .frame(height: 27)
                                .contentShape(.capsule)
                                .glassEffect(
                                    page == model.selectedPage
                                        ? .regular.tint(.white.opacity(0.12)).interactive()
                                        : .clear.interactive(),
                                    in: .capsule
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(page == model.selectedPage ? .isSelected : [])
                        .accessibilityIdentifier("notchium.page.\(page.rawValue)")
                    }
                }
            }
            NotchPageSwipeSurface(model: model, isEnabled: isExpanded && !auxiliaryInteractionPresented,
                                  reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, NotchGeometryResolver.expandedContentHorizontalInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages")
    }
}
