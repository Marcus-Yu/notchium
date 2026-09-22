import AppKit
import NotchiumDesignSystem
import NotchiumServices
import SwiftUI

struct AudioPageView: View {
    @Bindable var model: AudioFeatureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(.bottom, 20)
        .foregroundStyle(.white)
    }

    private var currentOutput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CURRENT OUTPUT")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.43))
            if let output = model.devices.currentOutput {
                HStack(spacing: 8) {
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
                Text("No output device")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
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
            columnTitle("LOCAL AUDIO APPS")
            ScrollView {
                LazyVStack(spacing: 5) {
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
            Text("Per-app gain needs a system audio driver.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func appRow(_ process: AudioProducingProcess) -> some View {
        HStack(spacing: 7) {
            if let icon = model.appIcon(process) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.fill").frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.appName(process))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text("Audio active")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.48))
            }
            Spacer(minLength: 2)
            if model.isPinned(process) {
                Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5))
            }
            Menu {
                Button("Open App") { model.activate(process) }
                if process.bundleID != nil {
                    Button(model.isPinned(process) ? "Unpin" : "Pin in Mixer") {
                        model.togglePin(process)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Actions for \(model.appName(process))")
        }
        .padding(.horizontal, 3)
        .frame(height: 32)
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
