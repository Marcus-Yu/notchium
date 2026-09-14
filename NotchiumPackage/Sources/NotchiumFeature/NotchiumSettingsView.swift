import NotchiumCore
import SwiftUI
import NotchiumMediaFeature
import NotchiumServices

public struct NotchiumSettingsView: View {
    private let environment: AppEnvironment
    private let audioMeter: SystemAudioMeter?

    public init(environment: AppEnvironment, audioMeter: SystemAudioMeter? = nil) {
        self.environment = environment
        self.audioMeter = audioMeter
    }

    public var body: some View {
        Form {
            if let media = environment.services.media as? RealMediaProvider {
                MediaConnectionView(provider: media)
            }
            if let audioMeter { AudioMeterPermissionView(meter: audioMeter) }
            Section("Distribution") {
                Text(environment.distributionProfile.rawValue)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 480)
    }
}
