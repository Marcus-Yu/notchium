#if DEBUG
import NotchiumCore
import NotchiumDebug
import NotchiumDynamicIsland
import SwiftUI
import NotchiumMediaFeature
import NotchiumServices

public struct NotchiumDeveloperPanelView: View {
    private let presentationModel: DynamicIslandPresentationModel
    private let uuids: any UUIDGenerating
    private let mediaModel: MediaFeatureModel
    private let mockMedia: MockMediaProvider
    private let realMedia: any MediaProviding
    private let model: DeveloperPanelModel
    private let shellDebugModel: NotchShellDebugModel

    public init(
        model: DeveloperPanelModel,
        shellDebugModel: NotchShellDebugModel,
        presentationModel: DynamicIslandPresentationModel,
        uuids: any UUIDGenerating,
        mediaModel: MediaFeatureModel, mockMedia: MockMediaProvider, realMedia: any MediaProviding
    ) {
        self.mediaModel = mediaModel; self.mockMedia = mockMedia; self.realMedia = realMedia
        self.presentationModel = presentationModel
        self.uuids = uuids
        self.model = model
        self.shellDebugModel = shellDebugModel
    }

    public var body: some View {
        DeveloperPanelView(model: model) {
            NotchShellDeveloperControls(model: shellDebugModel)
        } activityContent: {
            VStack(spacing: 12) {
                MediaDeveloperControls(model: mediaModel, mock: mockMedia, real: realMedia)
                NotchActivityDeveloperControls(presentation: presentationModel, uuids: uuids)
            }
        }
    }
}
#endif
