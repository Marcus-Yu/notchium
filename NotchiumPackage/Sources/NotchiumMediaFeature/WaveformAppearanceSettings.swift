import SwiftUI

public struct WaveformAppearanceSettings: View {
    @Bindable private var appearance: WaveformAppearanceModel
    @State private var hexInput: String
    @State private var invalidHex = false

    public init(appearance: WaveformAppearanceModel) {
        self.appearance = appearance
        _hexInput = State(initialValue: appearance.staticColor.hex)
    }

    public var body: some View {
        Section("Waveform colour") {
            Picker("Colour mode", selection: $appearance.mode) {
                ForEach(WaveformColorMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .accessibilityIdentifier("notchium.waveform.mode")

            if appearance.mode == .static {
                HStack {
                    Text("Presets")
                    Spacer()
                    ForEach(presets, id: \.name) { preset in
                        Button {
                            appearance.staticColor = preset.color
                        } label: {
                            Circle().fill(preset.color.color)
                                .overlay(Circle().strokeBorder(.gray.opacity(0.6), lineWidth: 1))
                                .overlay {
                                    if appearance.staticColor == preset.color {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(preset.color == .black || preset.color == .blue ? .white : .black)
                                    }
                                }
                                .frame(width: 22, height: 22)
                                .padding(3).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                        .accessibilityAddTraits(appearance.staticColor == preset.color ? .isSelected : [])
                        .help(preset.name)
                    }
                }
                ColorPicker("Custom colour", selection: Binding(
                    get: { appearance.staticColor.color },
                    set: { if let color = WaveformColor(color: $0) { appearance.staticColor = color } }
                ), supportsOpacity: false)
                HStack {
                    TextField("Hex code", text: $hexInput, prompt: Text("#FFFFFF"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyHex)
                        .accessibilityIdentifier("notchium.waveform.hex")
                    Button("Apply", action: applyHex)
                }
                Text(invalidHex ? "Enter a valid hex colour, such as #007AFF or #0AF." : "Use a 3- or 6-digit hex code, with or without #.")
                    .font(.caption).foregroundStyle(invalidHex ? .red : .secondary)
            } else {
                Text("Matches the primary colour of the current album artwork. Uses white when artwork is unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Dark colours are brightened so the waveform stays visible against the black notch.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: appearance.staticColor) { _, color in
            hexInput = color.hex; invalidHex = false
        }
        .onChange(of: appearance.mode) { _, _ in
            hexInput = appearance.staticColor.hex; invalidHex = false
        }
    }

    private var presets: [(name: String, color: WaveformColor)] {
        [("White", .white), ("Blue", .blue), ("Green", .green), ("Black", .black)]
    }

    private func applyHex() {
        invalidHex = !appearance.setStaticHex(hexInput)
        if !invalidHex { hexInput = appearance.staticColor.hex }
    }
}
