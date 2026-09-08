import NotchiumCore
import SwiftUI
import NotchiumMediaFeature
import NotchiumServices

public struct NotchiumSettingsView: View {
    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        Form {
            if let media = environment.services.media as? RealMediaProvider {
                MediaConnectionView(provider: media)
            }
            Section("Distribution") {
                Text(environment.distributionProfile.rawValue)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 480)
    }
}
