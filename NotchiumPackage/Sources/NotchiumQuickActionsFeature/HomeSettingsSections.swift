import SwiftUI
import NotchiumCore

/// The Home Page category in Settings.
public struct HomeSettingsSections: View {
    private let model: QuickActionsModel
    @State private var error: String?

    public init(model: QuickActionsModel) { self.model = model }

    public var body: some View {
        Section {
            ForEach(HomeSectionID.allCases) { section in
                Toggle(section == .shortcuts ? "Show shortcut row" : section.title, isOn: Binding(get: {
                    model.store.configuration.enabledSections.contains(section.rawValue)
                }, set: { enabled in
                    perform { try model.store.setSectionEnabled(section, enabled: enabled) }
                }))
            }
            Button("Reset Home Layout") { perform { try model.store.resetHomeLayout() } }
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.caption) }
        } header: {
            Text("Home Sections")
        } footer: {
            Text("Media stays left and Calendar stays right. Enabled shortcuts pinned to Home appear in a compact row below. Reset restores Media and Calendar and keeps your shortcuts.")
        }
        QuickActionsSettings(model: model, showReminders: false)
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation(); error = nil } catch { self.error = error.localizedDescription }
    }
}
