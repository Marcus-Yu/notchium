import SwiftUI

struct NotchAudioHUDView: View {
    let hud: NotchAudioHUD
    let action: () -> Void
    let hoverChanged: (Bool) -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: hud.kind == .outputChanged ? "headphones" : hud.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 18)
                    Text(hud.deviceName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if hud.kind == .outputChanged {
                        Text("Connected")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                if hud.kind == .volume {
                    if hud.isMuted {
                        Text("Muted")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    } else if let volume = hud.volume {
                        HStack(spacing: 10) {
                            GeometryReader { geometry in
                                Capsule().fill(.white.opacity(0.17))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(.white)
                                            .frame(width: geometry.size.width * min(max(volume, 0), 1))
                                    }
                            }
                            .frame(height: 3)
                            Text("\(Int((volume * 100).rounded()))%")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .frame(width: 35, alignment: .trailing)
                        }
                    } else {
                        Text("Volume unavailable")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .onHover(perform: hoverChanged)
        .help("Open Audio")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open Audio for \(hud.deviceName)")
        .accessibilityIdentifier("notchium.audio.hud")
    }
}
