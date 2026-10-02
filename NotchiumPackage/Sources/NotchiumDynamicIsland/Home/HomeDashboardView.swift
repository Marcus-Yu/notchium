import SwiftUI
import NotchiumCore
import NotchiumDesignSystem

/// Primary Media/Calendar row with an optional, bounded auxiliary shortcut strip.
struct HomeDashboardView: View {
    @ObservedObject var pages: NotchPageModel
    let media: (any NotchMediaRendering)?
    let calendar: (any NotchCalendarRendering)?
    var quickActions: (any NotchQuickActionsRendering)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sections = [HomeSectionID.media, .calendar].filter { (quickActions?.homeSections ?? [.media, .calendar]).contains($0) }
        let showsShortcuts = quickActions?.showsHomeActions == true
        GeometryReader { geometry in
            if sections.isEmpty && !showsShortcuts {
                VStack(spacing: 10) {
                    Text("Make Home yours").font(.system(size: 13, weight: .medium))
                    Text("Choose sections in Settings → Customize Home.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    SettingsLink { Text("Customize Home…") }.buttonStyle(.borderless)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let primaryHeight = max(0, geometry.size.height - (showsShortcuts ? HomeDashboardStyle.shortcutRegionHeight : 0))
                let availableWidth = max(0, geometry.size.width - (sections.count == 2 ? ExpandedPageStyle.columnGap + HomeDashboardStyle.dividerHeight : 0))
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: ExpandedPageStyle.columnGap / 2) {
                        if sections.contains(.media) {
                            content(.media)
                                .frame(width: sections.count == 1 ? geometry.size.width : availableWidth * HomeDashboardStyle.mediaFraction,
                                       height: primaryHeight)
                                .clipped()
                        }
                        if sections.count == 2 {
                            Rectangle().fill(.white.opacity(0.1))
                                .frame(width: HomeDashboardStyle.dividerHeight,
                                       height: max(0, primaryHeight - ExpandedPageStyle.Space.sm * 2))
                                .padding(.vertical, ExpandedPageStyle.Space.sm)
                                .accessibilityHidden(true)
                        }
                        if sections.contains(.calendar) {
                            content(.calendar)
                                .frame(width: sections.count == 1 ? geometry.size.width : availableWidth * (1 - HomeDashboardStyle.mediaFraction),
                                       height: primaryHeight)
                                .clipped()
                        }
                    }
                    .frame(height: primaryHeight)
                    .environment(\.homeUsesCompactLayout, showsShortcuts)
                    if showsShortcuts, let quickActions {
                        Rectangle().fill(.white.opacity(0.1))
                            .frame(height: HomeDashboardStyle.dividerHeight)
                            .padding(.vertical, ExpandedPageStyle.Space.xs)
                            .accessibilityHidden(true)
                        quickActions.homeActions().frame(height: HomeDashboardStyle.shortcutStripHeight)
                    }
                }
            }
        }
        .padding(.horizontal, NotchGeometryResolver.expandedContentHorizontalInset)
        .padding(.top, showsShortcuts ? ExpandedPageStyle.Space.xs : ExpandedPageStyle.topInset)
        .padding(.bottom, showsShortcuts ? ExpandedPageStyle.Space.sm : ExpandedPageStyle.bottomInset)
        .animation(reduceMotion ? NotchMotion.reduced : NotchMotion.page, value: showsShortcuts)
        .accessibilityIdentifier("notchium.home.dashboard")
    }

    @ViewBuilder private func content(_ section: HomeSectionID) -> some View {
        switch section {
        case .media:
            if let media { media.homeMedia { pages.selectedPage = .music } }
            else { unavailable("Music unavailable", page: .music) }
        case .calendar:
            if let calendar { calendar.homeCalendar { pages.selectedPage = .calendar } }
            else { unavailable("Calendar unavailable", page: .calendar) }
        case .shortcuts:
            EmptyView()
        }
    }
    private func unavailable(_ text: String, page: NotchPage) -> some View {
        Button { pages.selectedPage = page } label: {
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
