import SwiftUI

struct NotchPagesView: View {
    @ObservedObject var model: NotchPageModel

    var body: some View {
        Group {
            switch model.selectedPage {
            case .home: HomePagePlaceholder()
            case .media: MediaPagePlaceholder()
            case .system: SystemPagePlaceholder()
            case .utilities: UtilitiesPagePlaceholder()
            case .focus: FocusPagePlaceholder()
            }
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
