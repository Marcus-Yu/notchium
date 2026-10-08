import AppKit
import NotchiumDesignSystem
import NotchiumDynamicIsland
import NotchiumServices
import SwiftUI

enum AudioPageMetrics {
    static let appRowHeight: CGFloat = 52
    static let appRowSpacing: CGFloat = ExpandedPageStyle.Space.xs
    static let twoRowViewportHeight = appRowHeight * 2 + appRowSpacing
}

struct AudioPageView: View {
    @Bindable var model: AudioFeatureModel
    @Environment(\.notchAuxiliaryInteraction) private var auxiliaryInteraction

    var body: some View {
        VStack(alignment: .leading, spacing: ExpandedPageStyle.Space.sm) {
            currentOutput
            HStack(alignment: .top, spacing: 0) {
                outputColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.trailing, ExpandedPageStyle.Space.lg)
                Rectangle().fill(.white.opacity(0.13)).frame(width: 1)
                mixerColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.leading, ExpandedPageStyle.Space.lg)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, ExpandedPageStyle.outerInset)
        .padding(.top, ExpandedPageStyle.topInset)
        .padding(.bottom, ExpandedPageStyle.bottomInset)
        .foregroundStyle(.white)
    }

    private var currentOutput: some View {
        VStack(alignment: .leading, spacing: ExpandedPageStyle.Space.xs) {
            if let output = model.devices.currentOutput {
                HStack(spacing: 8) {
                    Text("Output")
                        .font(ExpandedPageStyle.sectionTitle)
                        .foregroundStyle(ExpandedPageStyle.secondary)
                    Image(systemName: outputSymbol(output))
                        .font(.system(size: 14, weight: .medium))
                    Text(output.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if let battery = model.state(for: output)?.battery,
                       case let .available(levels) = battery {
                        DeviceBatteryDetail(levels: levels)
                    }
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
                HStack(spacing: ExpandedPageStyle.Space.sm) {
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
                        .help(output.isMuted == true ? "Unmute system audio" : "Mute system audio")
                        .accessibilityLabel(output.isMuted == true ? "Unmute system audio" : "Mute system audio")
                    }
                }
                .frame(height: 20)
            } else {
                HStack(spacing: 8) {
                    Text("Output")
                        .font(ExpandedPageStyle.sectionTitle)
                        .foregroundStyle(ExpandedPageStyle.secondary)
                    Text("No output device")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var outputColumn: some View {
        VStack(alignment: .leading, spacing: ExpandedPageStyle.Space.xs) {
            columnTitle("Output Devices")
            ScrollView {
                LazyVStack(spacing: ExpandedPageStyle.Space.xs) {
                    ForEach(model.devices.outputs) { output in
                        Button { model.select(output) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: outputSymbol(output))
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
                            .frame(height: ExpandedPageStyle.controlSize)
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
        VStack(alignment: .leading, spacing: ExpandedPageStyle.Space.xs) {
            HStack(spacing: 6) {
                columnTitle("Local Audio Apps")
                Spacer(minLength: 4)
                if model.audioPermissionRequired {
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
                        Text(emptyMixerMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.52))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 5)
                            .fixedSize(horizontal: false, vertical: true)
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
                        .frame(width: ExpandedPageStyle.compactControlSize, height: ExpandedPageStyle.compactControlSize)
                }
                .buttonStyle(.plain)
                .help(muted ? "Unmute \(model.appName(process))" : "Mute \(model.appName(process))")
                .accessibilityLabel(muted ? "Unmute \(model.appName(process))" : "Mute \(model.appName(process))")
                AudioAppOptionsButton(
                    appName: model.appName(process),
                    isPinned: model.isPinned(process),
                    resetVolume: { model.resetAppVolume(process) },
                    togglePin: { model.togglePin(process) },
                    interactionBegan: auxiliaryInteraction.begin,
                    interactionEnded: auxiliaryInteraction.end(actionSelected:)
                )
                .frame(width: ExpandedPageStyle.compactControlSize, height: ExpandedPageStyle.compactControlSize)
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
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
        }
    }

    private var emptyMixerMessage: String {
        if model.audioPermissionRequired { return "Allow System Audio Recording to see local apps" }
        if model.mixerStatus == .unavailable { return "Per-app audio is unavailable right now" }
        return "No apps are producing audio"
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text)
            .font(ExpandedPageStyle.sectionTitle)
            .foregroundStyle(ExpandedPageStyle.secondary)
    }

    /// The same device category as the notch activity: AirPods glyphs only for AirPods.
    private func outputSymbol(_ output: AudioDevice) -> String {
        model.state(for: output)?.category.symbol ?? "speaker.wave.2"
    }
}

/// Only the components the source reported, e.g. "L 80%  R 75%  Case 40%". Never estimated.
struct DeviceBatteryDetail: View {
    let levels: DeviceBatteryLevels

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.components(levels), id: \.label) { component in
                Text(component.label.isEmpty ? component.value : "\(component.label) \(component.value)")
            }
            if levels.isCharging == true {
                Image(systemName: "bolt.fill").accessibilityLabel("Charging")
            }
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Battery")
    }

    static func components(_ levels: DeviceBatteryLevels) -> [(label: String, value: String)] {
        func percent(_ value: Double) -> String { "\(Int((min(max(value, 0), 1) * 100).rounded()))%" }
        var result: [(label: String, value: String)] = []
        if let single = levels.single { result.append(("", percent(single))) }
        if let left = levels.left { result.append(("L", percent(left))) }
        if let right = levels.right { result.append(("R", percent(right))) }
        if let caseLevel = levels.caseLevel { result.append(("Case", percent(caseLevel))) }
        return result
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
        button.focusRingType = .default
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = .white.withAlphaComponent(0.82)
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setAccessibilityLabel("Actions for \(appName)")
        button.toolTip = "Actions for \(appName)"
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateMenu()
        button.setAccessibilityLabel("Actions for \(appName)")
        button.toolTip = "Actions for \(appName)"
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
