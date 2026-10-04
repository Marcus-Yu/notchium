import AppKit
import NotchiumCore
import SwiftUI

struct NotchUtilityControls: View {
    let caffeine: (any NotchCaffeineControlling)?
    var camera: (any NotchCameraControlling)? = nil
    let quickReminder: (any NotchQuickActionsRendering)?
    let close: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if let caffeine { NotchCaffeineButton(controller: caffeine) }
                    if let camera { NotchCameraButton(camera: camera) }
                    if let quickReminder { quickReminder.reminderButton() }
                    NotchSettingsButton()
                }

                Spacer().frame(width: 18)

                NotchCloseButton(action: close)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notchium utilities")
    }
}

/// Opens a small mirror inside the expanded notch; selected while the camera is live.
private struct NotchCameraButton: View {
    let camera: any NotchCameraControlling

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let live = camera.isPreviewPresented
        Button(action: camera.togglePreview) {
            NotchUtilityLabel(symbol: live ? "web.camera.fill" : "web.camera", isHovered: isHovered, isSelected: live)
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.18), value: isHovered)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.18), value: live)
        .help(live ? "Close Mirror" : "Mirror")
        .accessibilityLabel("Mirror")
        .accessibilityValue(live ? "Camera on" : "Off")
        .accessibilityHint("Shows a live camera preview in the notch. Nothing is recorded.")
        .accessibilityAddTraits(live ? .isSelected : [])
        .accessibilityIdentifier("notchium.shell.camera")
    }
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
            NotchUtilityLabel(symbol: "gearshape.fill", isHovered: isHovered)
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
            NotchUtilityLabel(symbol: "xmark", isHovered: isHovered)
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

public struct NotchUtilityButtonStyle: ButtonStyle {
    public init() {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.16),
                       value: configuration.isPressed)
    }
}

/// Shared chrome for the utility group on the permanently dark notch surface.
public struct NotchUtilityLabel: View {
    let symbol: String
    let isHovered: Bool
    let isSelected: Bool
    let foreground: Color?
    let glass: Glass?

    public init(symbol: String, isHovered: Bool, isSelected: Bool = false,
                foreground: Color? = nil, glass: Glass? = nil) {
        self.symbol = symbol; self.isHovered = isHovered; self.isSelected = isSelected
        self.foreground = foreground; self.glass = glass
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground ?? .white.opacity(isHovered || isSelected ? 1 : 0.6))
            .frame(width: 28, height: 28)
            .background(.white.opacity(isSelected ? 0.14 : 0.06), in: .circle)
            .contentShape(.circle)
            .glassEffect(glass ?? (isHovered || isSelected
                ? .regular.tint(.white.opacity(0.1)).interactive()
                : .clear.interactive()), in: .circle)
    }
}
