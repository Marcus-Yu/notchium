#if DEBUG
import NotchiumDynamicIsland
import SwiftUI

struct NotchShellDeveloperControls: View {
    @Bindable var model: NotchShellDebugModel

    var body: some View {
        Form {
            Section("Display and surface") {
                Picker("Display source", selection: $model.displaySource) {
                    ForEach(NotchDebugDisplaySource.allCases, id: \.self) { source in
                        Text(label(for: source)).tag(source)
                    }
                }

                Picker("Surface mode", selection: $model.surfaceMode) {
                    ForEach(NotchDebugSurfaceMode.allCases, id: \.self) { mode in
                        Text(label(for: mode)).tag(mode)
                    }
                }

                Picker("Presentation", selection: $model.presentation) {
                    ForEach(NotchStableState.allCases, id: \.self) { state in
                        Text(state.rawValue.capitalized).tag(state)
                    }
                }
            }

            Section("Appearance and accessibility") {
                Picker("Appearance", selection: $model.appearance) {
                    ForEach(NotchAppearanceOverride.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized).tag(value)
                    }
                }
                Picker("Reduce Motion", selection: $model.reduceMotion) {
                    accessibilityOptions
                }
                Picker("Reduce Transparency", selection: $model.reduceTransparency) {
                    accessibilityOptions
                }
            }

            Section {
                Button("Reset to Automatic") {
                    model.resetToAutomatic()
                }
            } footer: {
                Text("These controls use the same override model as deterministic UI-test launch arguments. They are excluded from release builds.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var accessibilityOptions: some View {
        ForEach(NotchAccessibilityOverride.allCases, id: \.self) { value in
            Text(value.rawValue.capitalized).tag(value)
        }
    }

    private func label(for source: NotchDebugDisplaySource) -> String {
        switch source {
        case .live: "Live displays"
        case .builtInMock: "Built-in mock"
        case .externalMock: "External mock"
        }
    }

    private func label(for mode: NotchDebugSurfaceMode) -> String {
        switch mode {
        case .automatic: "Automatic"
        case .physical: "Physical simulation"
        case .virtual: "Virtual pill"
        }
    }
}
#endif
