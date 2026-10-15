import NotchiumDynamicIsland
import SwiftUI

struct NotchDisplaySettingsSection: View {
    let coordinator: NotchiumDisplayCoordinator

    private var selection: Binding<String> {
        Binding {
            let preferences = coordinator.settings.preferences
            return switch preferences.selection {
            case .builtIn: "builtIn"
            case .all: "all"
            case .selected: preferences.selectedDisplayKey ?? "builtIn"
            }
        } set: { value in
            var preferences = coordinator.settings.preferences
            if value == "builtIn" { preferences.selection = .builtIn }
            else if value == "all" { preferences.selection = .all }
            else {
                preferences.selection = .selected
                preferences.selectedDisplayKey = value
                preferences.selectedDisplayName = coordinator.displayState.availableDisplays
                    .first { $0.selectionKey == value }?.name
            }
            coordinator.settings.preferences = preferences
        }
    }

    var body: some View {
        @Bindable var settings = coordinator.settings
        Section("Displays") {
            Picker("Show Notchium on", selection: selection) {
                Text("Built-in display (Default)").tag("builtIn")
                Text("All displays").tag("all")
                ForEach(coordinator.displayState.availableDisplays, id: \.id) { display in
                    Text(display.isBuiltIn ? "\(display.name) (Built-in)" : display.name)
                        .tag(display.selectionKey)
                }
                if settings.preferences.selection == .selected,
                   let key = settings.preferences.selectedDisplayKey,
                   !coordinator.displayState.availableDisplays.contains(where: { $0.selectionKey == key }) {
                    Text("\(settings.preferences.selectedDisplayName ?? "Selected display") (Disconnected)")
                        .tag(key)
                }
            }
            .accessibilityIdentifier("notchium.settings.display.selection")

            Text("The default stays on your MacBook, even when you use another monitor. With all displays selected, each notch opens and closes independently.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Create a notch shape on displays without a notch", isOn: $settings.preferences.createsNotch)
                .accessibilityIdentifier("notchium.settings.display.createNotch")
            Text("The shape scales to the display using MacBook notch proportions. Turn this off to use a compact pill on notchless displays.")
                .font(.caption).foregroundStyle(.secondary)

            if settings.preferences.selection == .selected,
               !coordinator.displayState.availableDisplays.contains(where: {
                   $0.selectionKey == settings.preferences.selectedDisplayKey
               }) {
                Text("Your selected display is disconnected. Notchium uses the built-in display, or the main display if the built-in display is unavailable, until it reconnects.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
