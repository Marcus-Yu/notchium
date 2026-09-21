import SwiftUI

struct NotchExpandedPlaceholderContainer: View {
    let pageModel: NotchPageModel

    var body: some View {
        NotchPagesView(model: pageModel)
    }
}
