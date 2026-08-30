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

            Section("Runtime geometry") {
                Toggle("Show Notch Geometry", isOn: $model.showNotchGeometry)
                LabeledContent("Target display", value: model.runtimePlacement?.display.name ?? "No display")
                LabeledContent("Screen frame", value: format(model.runtimePlacement?.display.frame))
                LabeledContent("Visible frame", value: format(model.runtimePlacement?.display.visibleFrame))
                LabeledContent("Safe area", value: format(model.runtimePlacement?.display.safeAreaInsets))
                LabeledContent("Auxiliary left", value: format(model.runtimePlacement?.display.auxiliaryTopLeftArea))
                LabeledContent("Auxiliary right", value: format(model.runtimePlacement?.display.auxiliaryTopRightArea))
                LabeledContent("Hardware notch", value: format(model.runtimeLayout?.hardwareNotchGeometry?.frame))
                LabeledContent("Collapsed surface", value: format(model.runtimeLayout?.collapsedVisibleFrame))
                LabeledContent("Collapsed hover zone", value: format(model.runtimeLayout?.collapsedHoverFrame))
                LabeledContent("Panel frame", value: format(model.runtimeLayout?.panelFrame))
                LabeledContent(
                    "Hardware notch active",
                    value: model.runtimeLayout.map { $0.hasHardwareNotch ? "Yes" : "No" } ?? "Unavailable"
                )
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

    private func format(_ rect: CGRect?) -> String {
        guard let rect else { return "Unavailable" }
        return String(
            format: "x %.1f, y %.1f, w %.1f, h %.1f",
            rect.minX, rect.minY, rect.width, rect.height
        )
    }

    private func format(_ insets: NotchiumDisplayInsets?) -> String {
        guard let insets else { return "Unavailable" }
        return String(
            format: "top %.1f, left %.1f, bottom %.1f, right %.1f",
            insets.top, insets.leading, insets.bottom, insets.trailing
        )
    }
}
#endif
