#if DEBUG
import NotchiumDebug
import NotchiumDynamicIsland
import SwiftUI

public struct NotchiumDeveloperPanelView: View {
    private let model: DeveloperPanelModel
    private let shellDebugModel: NotchShellDebugModel

    public init(
        model: DeveloperPanelModel,
        shellDebugModel: NotchShellDebugModel
    ) {
        self.model = model
        self.shellDebugModel = shellDebugModel
    }

    public var body: some View {
        DeveloperPanelView(model: model) {
            NotchShellDeveloperControls(model: shellDebugModel)
        }
    }
}
#endif
