#if DEBUG
import NotchiumCore
import NotchiumDynamicIsland
import SwiftUI

struct NotchActivityDeveloperControls: View {
    let presentation: DynamicIslandPresentationModel
    @ObservedObject private var coordinator: ActivityCoordinator
    @ObservedObject private var pages: NotchPageModel
    private let uuids: any UUIDGenerating

    init(presentation: DynamicIslandPresentationModel, uuids: any UUIDGenerating) {
        self.presentation = presentation
        coordinator = presentation.activityCoordinator
        pages = presentation.pageModel
        self.uuids = uuids
    }

    private var sections: [String] {
        MockNotchActivity.allCases.filter { $0.section != "MEDIA" }.reduce(into: []) { result, event in
            if !result.contains(event.section) { result.append(event.section) }
        }
    }

    var body: some View {
        Form {
            Section("Live state") {
                LabeledContent("Active Activity", value: coordinator.activeActivity?.title ?? "None")
                LabeledContent("Priority", value: coordinator.activeActivity.map { String(describing: $0.priority) } ?? "—")
                LabeledContent("Queue Count", value: String(coordinator.queueCount))
                LabeledContent("Current Page", value: pages.selectedPage.rawValue)
                LabeledContent("Pinned", value: presentation.visualState == .expanded ? "Yes" : "No")
                LabeledContent("Expanded", value: presentation.surfaceState != .collapsed ? "Yes" : "No")
                Button("Clear Active Activity", action: coordinator.dismissActive)
                Button("Clear Queue", action: coordinator.clearQueue)
            }
            ForEach(sections, id: \.self) { section in
                Section(section) {
                    ForEach(MockNotchActivity.allCases.filter { $0.section == section }) { event in
                        Button(event.rawValue) {
                            Task {
                                let id = await uuids.next()
                                coordinator.present(event.activity(id: id))
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
#endif
