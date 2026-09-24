import AppKit
import NotchiumCore
import SwiftUI

struct NotchUtilityControls: View {
    let caffeine: (any NotchCaffeineControlling)?
    let keyboardLock: (any NotchKeyboardLockControlling)?
    let close: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if let caffeine { NotchCaffeineButton(controller: caffeine) }
                    if let keyboardLock { NotchKeyboardLockButton(controller: keyboardLock) }
                }

                Spacer().frame(width: 18)

                HStack(spacing: 8) {
                    NotchSettingsButton()
                    NotchCloseButton(action: close)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notchium utilities")
    }
}

private struct NotchCaffeineButton: View {
    let controller: any NotchCaffeineControlling

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: controller.cycleMode) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foregroundStyle)
                .frame(width: 28, height: 28)
                .contentShape(.circle)
                .glassEffect(glass, in: .circle)
        }
        .buttonStyle(CaffeinePressButtonStyle(
            allowsHold: controller.mode != .systemAndDisplay,
            holdAction: controller.keepDisplayAwake
        ))
        .disabled(controller.isBusy)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.18),
                   value: controller.mode)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.18),
                   value: isHovered)
        .help(tooltip)
        .accessibilityLabel("Caffeine")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Click to toggle Mac awake. Hold for three quarters of a second to keep the display awake too.")
        .accessibilityIdentifier("notchium.shell.caffeine")
    }

    private var glass: Glass {
        switch controller.mode {
        case .off:
            isHovered ? .regular.tint(.white.opacity(0.10)).interactive() : .clear.interactive()
        case .system:
            .regular.tint(.green.opacity(isHovered ? 0.60 : 0.48)).interactive()
        case .systemAndDisplay:
            .regular.tint(.blue.opacity(isHovered ? 0.64 : 0.52)).interactive()
        }
    }

    private var foregroundStyle: Color {
        switch controller.mode {
        case .off: .white.opacity(isHovered ? 1 : 0.60)
        case .system: .green
        case .systemAndDisplay: .blue
        }
    }

    private var tooltip: String {
        switch controller.mode {
        case .off: "Keep Mac Awake"
        case .system: "Mac Awake · Display Can Sleep"
        case .systemAndDisplay: "Mac + Display Awake"
        }
    }

    private var accessibilityValue: String {
        switch controller.mode {
        case .off: "Off"
        case .system: "Keeping Mac awake"
        case .systemAndDisplay: "Keeping Mac and display awake"
        }
    }
}

private struct NotchKeyboardLockButton: View {
    let controller: any NotchKeyboardLockControlling

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: controller.toggleLock) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(controller.isLocked ? .orange : .white.opacity(isHovered ? 1 : 0.60))
                .frame(width: 28, height: 28)
                .contentShape(.circle)
                .overlay {
                    progressRing(
                        active: controller.emergencyUnlockStartedAt != nil,
                        duration: 2,
                        color: .orange
                    )
                }
                .glassEffect(
                    controller.isLocked
                        ? .regular.tint(.orange.opacity(isHovered ? 0.48 : 0.34)).interactive()
                        : isHovered
                            ? .regular.tint(.white.opacity(0.10)).interactive()
                            : .clear.interactive(),
                    in: .circle
                )
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .disabled(controller.isBusy)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.18),
                   value: controller.isLocked)
        .help(controller.isLocked ? "Unlock Keyboard" : "Lock Keyboard")
        .accessibilityLabel(controller.isLocked ? "Unlock Keyboard" : "Lock Keyboard")
        .accessibilityValue(controller.isLocked ? "Locked" : "Unlocked")
        .accessibilityHint(controller.isLocked ? "Hold Command, Option, and Escape for two seconds to unlock." : "Mouse and trackpad remain available.")
        .accessibilityIdentifier("notchium.shell.keyboardLock")
        .alert(guidanceTitle, isPresented: guidancePresented) {
            if case .permissionsRequired = controller.guidance {
                Button("Open System Settings", action: controller.openSystemSettings)
                Button("Not Now", role: .cancel, action: controller.dismissGuidance)
            } else {
                Button("OK", action: controller.dismissGuidance)
            }
        } message: {
            Text(guidanceMessage)
        }
    }

    private var guidancePresented: Binding<Bool> {
        Binding(
            get: { controller.guidance != nil },
            set: { if !$0 { controller.dismissGuidance() } }
        )
    }

    private var guidanceTitle: String {
        switch controller.guidance {
        case .permissionsRequired: "Keyboard Permission Required"
        case .firstLock: "Keyboard Locked"
        case .lockEnded: "Keyboard Lock Ended"
        case .unavailable, .secureInputEnabled: "Keyboard Lock Unavailable"
        case nil: "Keyboard Lock"
        }
    }

    private var guidanceMessage: String {
        switch controller.guidance {
        case let .permissionsRequired(permissions):
            let names = permissions.sorted { $0.rawValue < $1.rawValue }.map {
                $0 == .inputMonitoring ? "Input Monitoring" : "Accessibility"
            }
            return "Allow Notchium in \(names.joined(separator: " and ")) to block keyboard input. The lock is currently off."
        case .firstLock:
            return "Keyboard locked. Hold ⌘⌥Esc for 2 seconds to unlock."
        case .lockEnded:
            return "macOS disabled the input event tap, so Notchium unlocked immediately."
        case .secureInputEnabled:
            return "macOS Secure Input is active, so Notchium cannot block keyboard input. The lock is off. Leave any password field or turn off Secure Keyboard Entry in the app that enabled it, then try again."
        case .unavailable:
            return "Notchium could not start the keyboard event tap. The keyboard remains unlocked."
        case nil:
            return ""
        }
    }
}

@ViewBuilder
private func progressRing(active: Bool, duration: TimeInterval, color: Color) -> some View {
    Circle()
        .trim(from: 0, to: active ? 1 : 0)
        .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .padding(1)
        .animation(active ? .linear(duration: duration) : .easeOut(duration: 0.12), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
}

/// App utility in the expanded header, outside the media controls.
private struct NotchSettingsButton: View {
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
