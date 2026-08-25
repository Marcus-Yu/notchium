import NotchiumCore
import SwiftUI

public struct NotchiumSettingsView: View {
    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        Form {
            Section("Stage 1") {
                LabeledContent("Architecture", value: "Ready")
                LabeledContent(
                    "Distribution",
                    value: environment.distributionProfile.rawValue
                )
                LabeledContent("Feature implementations", value: "Disabled")
            }

            Section("Product contract") {
                Text("Minimal when collapsed. Useful when hovered. Powerful when deliberately opened.")
                Text("All protected features remain off until enabled and first used in a later stage.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 300)
    }
}
