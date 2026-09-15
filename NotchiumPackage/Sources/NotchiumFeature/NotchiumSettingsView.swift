import NotchiumCore
import SwiftUI
import NotchiumMediaFeature
import NotchiumServices

public struct NotchiumSettingsView: View {
    private let environment: AppEnvironment
    private let audioMeter: SystemAudioMeter?
    private let menuBarInsertion: Binding<Bool>?

    public init(environment: AppEnvironment, audioMeter: SystemAudioMeter? = nil,
                menuBarInsertion: Binding<Bool>? = nil) {
        self.environment = environment
        self.audioMeter = audioMeter
        self.menuBarInsertion = menuBarInsertion
    }

    public var body: some View {
        Form {
            if let menuBarInsertion {
                Section("Menu Bar") {
                    Toggle("Show menu-bar icon", isOn: menuBarInsertion)
                    Text("If macOS blocks the icon, allow Notchium in System Settings → Menu Bar. Settings is always available from the expanded notch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
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
