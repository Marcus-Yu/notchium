import SwiftUI
import NotchiumDesignSystem

/// Fixed composition only. Feature models and provider lifetimes remain outside Home.
struct HomeDashboardView: View {
    @ObservedObject var pages: NotchPageModel
    let media: (any NotchMediaRendering)?
    let calendar: (any NotchCalendarRendering)?
    var quickActions: (any NotchQuickActionsRendering)?

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let availableWidth = max(0, geometry.size.width - ExpandedPageStyle.columnGap)
                HStack(spacing: ExpandedPageStyle.columnGap) {
                    Group {
                        if let media {
                            media.homeMedia { pages.selectedPage = .music }
                        } else { unavailable("Music unavailable", page: .music) }
                    }
                    .frame(width: availableWidth * 0.62, height: geometry.size.height)


                    Group {
                        if let calendar {
                            calendar.homeCalendar { pages.selectedPage = .calendar }
                        } else { unavailable("Calendar unavailable", page: .calendar) }
                    }
                    .frame(width: availableWidth * 0.38, height: geometry.size.height)
                }
            }
            if let quickActions, quickActions.showsHomeActions {
                quickActions.homeActions().frame(height: 30)
            }
        }
        .padding(.horizontal, NotchGeometryResolver.expandedContentHorizontalInset)
        .padding(.top, ExpandedPageStyle.topInset)
        .padding(.bottom, ExpandedPageStyle.bottomInset)
        .accessibilityIdentifier("notchium.home.dashboard")
    }

    private func unavailable(_ text: String, page: NotchPage) -> some View {
        Button { pages.selectedPage = page } label: {
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
