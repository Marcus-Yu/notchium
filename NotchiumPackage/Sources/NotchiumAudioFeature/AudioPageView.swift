import AppKit
import NotchiumDesignSystem
import NotchiumDynamicIsland
import NotchiumServices
import SwiftUI

enum AudioPageMetrics {
    static let appRowHeight: CGFloat = 54
    static let appRowSpacing: CGFloat = 5
    static let twoRowViewportHeight = appRowHeight * 2 + appRowSpacing
}

struct AudioPageView: View {
    @Bindable var model: AudioFeatureModel
    @Environment(\.notchAuxiliaryInteraction) private var auxiliaryInteraction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            currentOutput
            HStack(alignment: .top, spacing: 0) {
                outputColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.trailing, 16)
                Rectangle().fill(.white.opacity(0.13)).frame(width: 1)
                mixerColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.leading, 16)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
    }

    private var currentOutput: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let output = model.devices.currentOutput {
                HStack(spacing: 8) {
                    Text("CURRENT OUTPUT")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(.white.opacity(0.43))
                    Image(systemName: outputSymbol(output.name))
                        .font(.system(size: 14, weight: .medium))
                    Text(output.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if output.isMuted == true {
                        Text("Muted")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.64))
                    } else if let volume = output.volume {
                        Text("\(Int(((model.displayVolume ?? volume) * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.64))
                    }
                }
                HStack(spacing: 10) {
                    if let volume = output.volume {
                        NotchiumSlider(
                            value: Binding(
                                get: { model.displayVolume ?? volume },
                                set: { model.changeVolume($0) }
                            ),
                            accessibilityLabel: "System volume",
                            accessibilityStep: 0.05,
                            accessibilityValue: { "\(Int(($0 * 100).rounded())) percent" },
                            onEditingChanged: { editing in
                                model.setVolumeEditing(editing)
                                if !editing { model.changeVolume(model.displayVolume ?? volume, finished: true) }
                            }
                        )
                        .disabled(!output.canSetVolume)
                    } else {
                        Text("Volume is controlled by this output device")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if output.canSetMute {
                        Button { model.toggleMute() } label: {
                            Image(systemName: output.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 12))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(output.isMuted == true ? "Unmute system audio" : "Mute system audio")
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text("CURRENT OUTPUT")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(.white.opacity(0.43))
                    Text("No output device")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private var outputColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            columnTitle("OUTPUT DEVICES")
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.devices.outputs) { output in
                        Button { model.select(output) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: outputSymbol(output.name))
                                    .font(.system(size: 12))
                                    .frame(width: 16)
                                Text(output.name)
                                    .font(.system(size: 11, weight: output.isDefaultOutput ? .semibold : .regular))
                                    .lineLimit(1)
                                Spacer(minLength: 3)
                                if output.isDefaultOutput {
                                    Circle().fill(.white).frame(width: 5, height: 5)
                                } else if let volume = output.volume {
                                    Text("\(Int((volume * 100).rounded()))%")
                                        .font(.system(size: 9).monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(output.isDefaultOutput ? .white.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(output.name)\(output.isDefaultOutput ? ", current output" : "")")
                    }
                }
            }
            .scrollIndicators(.hidden)
            if let error = model.errorMessage {
                Text(error).font(.system(size: 9)).foregroundStyle(.orange.opacity(0.85))
            }
        }
    }

    private var mixerColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                columnTitle("LOCAL AUDIO APPS")
                Spacer(minLength: 4)
                if model.mixerStatus == .permissionRequired {
                    Menu {
                        Button("Request Access") { model.retryMixerPermission() }
                        Button("Open Privacy & Security") { model.openAudioPrivacySettings() }
                    } label: {
                        Label("Audio Access", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    .menuStyle(.borderlessButton)
                    .help("System Audio Recording permission is required")
                } else if model.mixerStatus == .unavailable {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .help("Per-app audio is temporarily unavailable; direct audio is restored")
                }
            }
            ScrollView {
                LazyVStack(spacing: AudioPageMetrics.appRowSpacing) {
                    if model.visibleProcesses.isEmpty {
                        Text("No apps are producing audio")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.52))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 5)
                    }
                    ForEach(model.visibleProcesses) { process in
                        appRow(process)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: AudioPageMetrics.twoRowViewportHeight)
        }
    }

    private func appRow(_ process: AudioProducingProcess) -> some View {
        let volume = model.appVolume(process)
        let muted = model.isAppMuted(process)
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                if let icon = model.appIcon(process) {
                    Image(nsImage: icon).resizable().frame(width: 17, height: 17)
                } else {
                    Image(systemName: "app.fill").frame(width: 17, height: 17)
                }
                Circle().fill(.green.opacity(0.9)).frame(width: 4, height: 4)
                    .accessibilityLabel("Audio active")
                Text(model.appName(process))
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(muted ? "Muted" : "\(Int((volume * 100).rounded()))%")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(width: 37, alignment: .trailing)
                Button { model.toggleAppMute(process) } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(muted ? "Unmute \(model.appName(process))" : "Mute \(model.appName(process))")
                AudioAppOptionsButton(
                    appName: model.appName(process),
                    isPinned: model.isPinned(process),
                    resetVolume: { model.resetAppVolume(process) },
                    togglePin: { model.togglePin(process) },
                    interactionBegan: auxiliaryInteraction.begin,
                    interactionEnded: auxiliaryInteraction.end(actionSelected:)
                )
                .frame(width: 17, height: 18)
                .accessibilityLabel("Actions for \(model.appName(process))")
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 27)
                NotchiumSlider(
                    value: Binding(get: { model.appVolume(process) },
                                   set: { model.setAppVolume($0, process: process) }),
                    accessibilityLabel: "\(model.appName(process)) volume",
                    accessibilityStep: 0.05,
                    accessibilityValue: { "\(Int(($0 * 100).rounded())) percent" },
                    onEditingChanged: { editing in
                        if !editing { model.commitAppVolume(process) }
                    }
                )
            }
        }
        .padding(.horizontal, 3)
        .frame(height: AudioPageMetrics.appRowHeight)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.9)
            .foregroundStyle(.white.opacity(0.46))
    }

    private func outputSymbol(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpod") || lower.contains("headphone") { return "headphones" }
        if lower.contains("display") || lower.contains("monitor") { return "display" }
        return "speaker.wave.2"
    }
}

struct AudioAppOptionsButton: NSViewRepresentable {
    let appName: String
    let isPinned: Bool
    let resetVolume: () -> Void
    let togglePin: () -> Void
    let interactionBegan: () -> Void
    let interactionEnded: (Bool) -> Void

    static func itemTitles(isPinned: Bool) -> [String] {
        ["Reset Volume to 100%", isPinned ? "Unpin from Mixer" : "Pin in Mixer"]
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = .white.withAlphaComponent(0.82)
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setAccessibilityLabel("Actions for \(appName)")
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateMenu()
        button.setAccessibilityLabel("Actions for \(appName)")
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: AudioAppOptionsButton
        weak var button: NSButton?
        private let menu = NSMenu()
        private lazy var resetItem = menuItem(action: #selector(resetVolume))
        private lazy var pinItem = menuItem(action: #selector(togglePin))
        private var actionSelected = false

        init(parent: AudioAppOptionsButton) {
            self.parent = parent
            super.init()
            menu.autoenablesItems = false
            menu.delegate = self
            menu.addItem(resetItem)
            menu.addItem(pinItem)
            updateMenu()
        }

        isolated deinit {
            parent.interactionEnded(actionSelected)
        }

        func updateMenu() {
            let titles = AudioAppOptionsButton.itemTitles(isPinned: parent.isPinned)
            resetItem.title = titles[0]
            pinItem.title = titles[1]
        }

        @objc func showMenu(_ sender: NSButton) {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY - 3),
                       in: sender)
        }

        func menuWillOpen(_ menu: NSMenu) {
            actionSelected = false
            parent.interactionBegan()
        }

        func menuDidClose(_ menu: NSMenu) {
            parent.interactionEnded(actionSelected)
            actionSelected = false
        }

        @objc private func resetVolume() {
            actionSelected = true
            parent.resetVolume()
        }

        @objc private func togglePin() {
            actionSelected = true
            parent.togglePin()
        }

        private func menuItem(action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = true
            return item
        }
    }
}
