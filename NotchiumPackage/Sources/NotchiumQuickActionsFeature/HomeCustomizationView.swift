import SwiftUI
import NotchiumCore

/// Native Settings editor, intentionally separate from the compact launcher surface.
public struct HomeCustomizationView: View {
    let model: QuickActionsModel
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    public init(model: QuickActionsModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Customize Home").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Form {
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
            }.formStyle(.grouped)
        }
        .frame(width: 570, height: 620)
        .accessibilityIdentifier("notchium.home.customization")
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); error = nil } catch { self.error = error.localizedDescription }
    }
}
