import AppKit
import SwiftUI

public struct AudioMeterPermissionView: View {
    @ObservedObject private var meter: SystemAudioMeter
    public init(meter: SystemAudioMeter) { self.meter = meter }
    public var body: some View {
        Section("Audio waveform") {
            Text(message).font(.caption).foregroundStyle(.secondary)
            if meter.status == .permissionRequired || meter.status == .unavailable || meter.status == .idle {
                Button("Enable system audio waveform") { meter.requestPermission() }
                Button("Open Recording Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
    private var message: String {
        switch meter.status {
        case .idle: "System audio is analyzed only during playback. Audio is never saved."
        case .starting: "Starting system audio analysis…"
        case .capturing: "Waveform follows Spotify audio only."
        case .permissionRequired: "System Audio Recording permission is required for Spotify's audio-reactive waveform. Bars remain static until access is granted."
        case .unavailable: "Spotify audio capture is unavailable. Start Spotify, then retry the waveform."
        }
    }
}
