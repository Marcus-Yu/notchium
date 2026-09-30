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
                LabeledContent("Primary", value: coordinator.primary.map { "\($0.key)" } ?? "None")
                LabeledContent("Secondary", value: coordinator.secondary.map { "\($0.key)" } ?? "None")
                LabeledContent("Priority", value: coordinator.activeActivity.map { String(describing: $0.priority) } ?? "—")
                LabeledContent("Queue Count", value: String(coordinator.queueCount))
                Text(coordinator.debugSummary)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                LabeledContent("Current Page", value: pages.selectedPage.rawValue)
                LabeledContent("Pinned", value: presentation.visualState == .expanded ? "Yes" : "No")
                LabeledContent("Expanded", value: presentation.surfaceState != .collapsed ? "Yes" : "No")
                Button("Clear Active Activity", action: coordinator.dismissActive)
                Button("Clear Queue", action: coordinator.clearQueue)
            }
            // Real production notifications through the real coordinator; no hardware state changes.
            Section("Device & Battery Simulation") {
                ForEach(Self.simulations, id: \.0) { title, notification in
                    Button(title) { presentation.notificationCoordinator.present(notification()) }
                }
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

    private static let simulations: [(String, @MainActor () -> NotchNotification)] = [
        ("Charger Connected · 37%", { .charging(level: 0.37) }),
        ("Charger Disconnected · 64%", { .powerDisconnected(level: 0.64) }),
        ("Low Battery · 19%", { .lowBattery(level: 0.19) }),
        ("Critical Battery · 8%", { .criticalBattery(level: 0.08) }),
        ("AirPods Pro Connected", { .audio(device(.outputChanged, "AirPods Pro", .airPodsPro)) }),
        ("AirPods Pro Connected · reported 80%", {
            .audio(device(.outputChanged, "AirPods Pro", .airPodsPro, battery: .init(level: 0.8, isCharging: false)))
        }),
        ("AirPods Pro Disconnected", { .audio(device(.deviceDisconnected, "AirPods Pro", .airPodsPro)) }),
        ("Headphones Connected", { .audio(device(.outputChanged, "Headphones", .headphones)) }),
        ("MacBook Speakers Connected", { .audio(device(.outputChanged, "MacBook Speakers", .builtIn)) }),
    ]

    private static func device(_ kind: NotchAudioHUD.Kind, _ name: String, _ style: NotchDeviceStyle,
                               battery: NotchDeviceBattery? = nil) -> NotchAudioHUD {
        NotchAudioHUD(kind: kind, deviceName: name, volume: nil, isMuted: false,
                      deviceStyle: style, deviceID: "simulated.\(style.rawValue)", battery: battery)
    }
}
#endif
