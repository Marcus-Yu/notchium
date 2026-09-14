import SwiftUI

struct NotchPagesView: View {
    @ObservedObject var model: NotchPageModel

    var body: some View {
        VStack(spacing: 14) {
            Group {
                switch model.selectedPage {
                case .home: HomePagePlaceholder()
                case .media: MediaPagePlaceholder()
                case .system: SystemPagePlaceholder()
                case .utilities: UtilitiesPagePlaceholder()
                case .focus: FocusPagePlaceholder()
                }
            }
            HStack(spacing: 8) {
                ForEach(model.enabledPages) { page in
                    Circle()
                        .fill(.white.opacity(page == model.selectedPage ? 0.8 : 0.2))
                        .frame(width: 5, height: 5)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { NotchPageSwipeSurface(model: model) }
        .accessibilityElement(children: .contain)
        .accessibilityValue(model.selectedPage.rawValue)
        .accessibilityHint("Swipe horizontally to change page")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.moveSelection(forward: true)
            case .decrement: model.moveSelection(forward: false)
            @unknown default: break
            }
        }
    }
}
