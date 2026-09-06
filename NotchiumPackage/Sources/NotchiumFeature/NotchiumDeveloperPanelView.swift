#if DEBUG
import NotchiumCore
import NotchiumDebug
import NotchiumDynamicIsland
import SwiftUI

public struct NotchiumDeveloperPanelView: View {
    private let presentationModel: DynamicIslandPresentationModel
    private let uuids: any UUIDGenerating
    private let model: DeveloperPanelModel
    private let shellDebugModel: NotchShellDebugModel

    public init(
        model: DeveloperPanelModel,
        shellDebugModel: NotchShellDebugModel,
        presentationModel: DynamicIslandPresentationModel,
        uuids: any UUIDGenerating
    ) {
        self.presentationModel = presentationModel
        self.uuids = uuids
        self.model = model
        self.shellDebugModel = shellDebugModel
    }

    public var body: some View {
        DeveloperPanelView(model: model) {
            NotchShellDeveloperControls(model: shellDebugModel)
        } activityContent: {
            NotchActivityDeveloperControls(presentation: presentationModel, uuids: uuids)
        }
    }
}
#endif
