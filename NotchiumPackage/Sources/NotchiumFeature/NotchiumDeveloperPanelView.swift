#if DEBUG
import NotchiumDebug
import SwiftUI

public struct NotchiumDeveloperPanelView: View {
    private let model: DeveloperPanelModel

    public init(model: DeveloperPanelModel) {
        self.model = model
    }

    public var body: some View {
        DeveloperPanelView(model: model)
    }
}
#endif
