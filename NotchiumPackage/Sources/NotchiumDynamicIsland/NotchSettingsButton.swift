import AppKit
import SwiftUI

struct NotchUtilityControls: View {
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            NotchSettingsButton()
            NotchCloseButton(action: close)
        }
    }
}

/// App utility in the expanded header, outside the media controls.
struct NotchSettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .contentShape(.circle)
                .glassEffect(
                    isHovered
                        ? .regular.tint(.white.opacity(0.1)).interactive()
                        : .clear.interactive(),
                    in: .circle
                )
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.18), value: isHovered)
        .help("Settings")
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("notchium.shell.settings")
    }
}

private struct NotchCloseButton: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovered ? 1 : 0.6))
                .frame(width: 28, height: 28)
                .contentShape(.circle)
                .glassEffect(
                    isHovered
                        ? .regular.tint(.white.opacity(0.1)).interactive()
                        : .clear.interactive(),
                    in: .circle
                )
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .keyboardShortcut(.cancelAction)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.18), value: isHovered)
        .help("Close Notchium")
        .accessibilityLabel("Close Notchium")
        .accessibilityIdentifier("notchium.shell.close")
    }
}

private struct NotchUtilityButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.16),
                       value: configuration.isPressed)
    }
}
