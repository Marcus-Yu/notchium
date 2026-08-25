#if DEBUG
import NotchDebug
import SwiftUI

public struct NotchDeveloperPanelView: View {
    private let model: DeveloperPanelModel

    public init(model: DeveloperPanelModel) {
        self.model = model
    }

    public var body: some View {
        DeveloperPanelView(model: model)
    }
}
#endif
