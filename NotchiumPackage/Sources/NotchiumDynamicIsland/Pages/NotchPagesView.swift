import SwiftUI

/// One selection owns top-level navigation; feature renderers keep their models alive.
struct NotchPagesView: View {
    @ObservedObject var model: NotchPageModel
    let mediaRenderer: (any NotchMediaRendering)?
    let calendarRenderer: (any NotchCalendarRendering)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pageAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.22)
    }

    var body: some View {
        VStack(spacing: 0) {
            navigation
                .frame(height: 42)

            ZStack {
                Group {
                    if let mediaRenderer {
                        mediaRenderer.expandedMedia()
                    } else {
                        MediaPagePlaceholder()
                    }
                }
                .environment(\.notchMediaPageVisible, model.selectedPage == .music)
                .opacity(model.selectedPage == .music ? 1 : 0)
                .offset(y: reduceMotion || model.selectedPage == .music ? 0 : 3)
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
                .offset(y: reduceMotion || model.selectedPage == .calendar ? 0 : 3)
                .allowsHitTesting(model.selectedPage == .calendar)
                .accessibilityHidden(model.selectedPage != .calendar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(pageAnimation, value: model.selectedPage)
        .overlay { NotchPageSwipeSurface(model: model) }
        .accessibilityElement(children: .contain)
        .accessibilityValue(model.selectedPage.title)
        .accessibilityHint("Swipe horizontally to change page")
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NotchGeometryResolver.expandedContentHorizontalInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages")
    }
}
