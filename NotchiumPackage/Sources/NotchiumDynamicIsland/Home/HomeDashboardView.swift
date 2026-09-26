import SwiftUI

/// Fixed composition only. Feature models and provider lifetimes remain outside Home.
struct HomeDashboardView: View {
    @ObservedObject var pages: NotchPageModel
    let media: (any NotchMediaRendering)?
    let calendar: (any NotchCalendarRendering)?

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 22)
            HStack(spacing: 22) {
                Group {
                    if let media {
                        media.homeMedia { pages.selectedPage = .music }
                    } else { unavailable("Music unavailable", page: .music) }
                }
                .frame(width: availableWidth * 0.62, height: geometry.size.height)
                .background(.white.opacity(0.045), in: .rect(cornerRadius: 16))

                Group {
                    if let calendar {
                        calendar.homeCalendar { pages.selectedPage = .calendar }
                    } else { unavailable("Calendar unavailable", page: .calendar) }
                }
                .frame(width: availableWidth * 0.38, height: geometry.size.height)
            }
        }
        .padding(.horizontal, NotchGeometryResolver.expandedContentHorizontalInset)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .accessibilityIdentifier("notchium.home.dashboard")
    }

    private func unavailable(_ text: String, page: NotchPage) -> some View {
        Button { pages.selectedPage = page } label: {
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
