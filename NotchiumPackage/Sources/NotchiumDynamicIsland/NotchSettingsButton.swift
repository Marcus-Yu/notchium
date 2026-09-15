import AppKit
import SwiftUI

/// App utility in the expanded header, outside the media controls.
struct NotchSettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    @State private var isHovered = false

    var body: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(isHovered ? 1 : 0.6))
                .frame(width: 28, height: 28)
                .background(.white.opacity(isHovered ? 0.14 : 0.04), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Settings")
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("notchium.shell.settings")
    }
}
