import NotchiumCore
import NotchiumDesignSystem
import NotchiumDynamicIsland
import SwiftUI

/// The reader leads. The script's name heads the page (no separate title); every control uses the
/// notch's own glyph buttons, and color is reserved for the reading marker and progress.
struct TeleprompterPage: View {
    @Bindable var model: TeleprompterModel
    var prepareToRead: @MainActor () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            if model.selectedScript == nil {
                topBar
                emptyState
            } else {
                topBar
                TeleprompterReadingText(session: model.session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                TeleprompterProgressLine(fraction: model.session.fraction)
                    .padding(.top, ExpandedPageStyle.Space.sm)
                controls
                    .padding(.top, ExpandedPageStyle.Space.xs)
                status
            }
        }
        .padding(.horizontal, ExpandedPageStyle.outerInset)
        .padding(.top, ExpandedPageStyle.Space.xs)
        .padding(.bottom, ExpandedPageStyle.Space.sm)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notchium.teleprompter.page")
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: ExpandedPageStyle.controlGap) {
            if !model.scripts.isEmpty {
                Picker("Script", selection: Binding(get: { model.selectedScriptID }, set: { id in
                    if let id { model.selectScript(id) }
                })) {
                    ForEach(model.scripts) { script in Text(script.title).tag(Optional(script.id)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize()
                .frame(maxWidth: 260, alignment: .leading)
                .disabled(model.session.isActive)
                .help(model.session.isActive ? "Pause to change scripts" : "Choose a script")
                .accessibilityIdentifier("notchium.teleprompter.script")
            }
            Spacer(minLength: 0)
            if model.selectedScript != nil { fontSizeControl }
            TeleprompterGlyphButton(title: "Edit Scripts…", symbol: "square.and.pencil", action: model.editScripts)
                .accessibilityIdentifier("notchium.teleprompter.edit")
        }
        .frame(height: ExpandedPageStyle.headerControlSize)
    }

    private var fontSizeControl: some View {
        @Bindable var session = model.session
        return HStack(spacing: 2) {
            TeleprompterGlyphButton(title: "Decrease reader text size", symbol: "textformat.size.smaller") {
                session.fontSize = max(TeleprompterReaderStyle.fontRange.lowerBound, session.fontSize - 1)
            }
            .disabled(session.fontSize <= TeleprompterReaderStyle.fontRange.lowerBound)
            .accessibilityIdentifier("notchium.teleprompter.font.decrease")
            Text("\(Int(session.fontSize)) pt")
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(ExpandedPageStyle.secondary)
                .frame(width: 34)
                .accessibilityLabel("Reader text size")
                .accessibilityValue("\(Int(session.fontSize)) points")
                .accessibilityIdentifier("notchium.teleprompter.font.value")
            TeleprompterGlyphButton(title: "Increase reader text size", symbol: "textformat.size.larger") {
                session.fontSize = min(TeleprompterReaderStyle.fontRange.upperBound, session.fontSize + 1)
            }
            .disabled(session.fontSize >= TeleprompterReaderStyle.fontRange.upperBound)
            .accessibilityIdentifier("notchium.teleprompter.font.increase")
        }
        .help("Adjust reader text size while reading")
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: ExpandedPageStyle.Space.sm) {
            Image(systemName: "text.alignleft").font(.system(size: 20, weight: .medium)).foregroundStyle(.tint)
            Text("Your words, near the camera").font(.system(size: 13, weight: .semibold))
            Text(model.errorMessage ?? "Paste a script or import a Word, RTF, or text file.")
                .font(.system(size: 11)).foregroundStyle(ExpandedPageStyle.secondary)
                .multilineTextAlignment(.center)
            Group {
                if !model.libraryLoaded, model.errorMessage != nil {
                    Button("Retry Library", action: model.start)
                } else {
                    Button("Create a Script…", action: model.editScripts)
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .padding(.top, ExpandedPageStyle.Space.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Controls

    private var controls: some View {
        @Bindable var session = model.session
        return HStack(spacing: ExpandedPageStyle.controlGap) {
            Picker("Scrolling mode", selection: $session.mode) {
                ForEach(TeleprompterMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
            .fixedSize()
            .help("Scrolling mode")
            .accessibilityIdentifier("notchium.teleprompter.mode")
            if session.mode != .voiceFollow {
                TeleprompterPaceControl(wordsPerMinute: $session.wordsPerMinute)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                TeleprompterGlyphButton(title: "Restart", symbol: "backward.end.fill", action: session.restart)
                TeleprompterGlyphButton(title: "Previous paragraph", symbol: "chevron.up") {
                    session.moveParagraph(forward: false)
                }
                // The one primary action: the same white disc as Music's Play/Pause.
                TeleprompterGlyphButton(title: session.isActive ? "Pause teleprompter" : "Start teleprompter",
                                        symbol: session.isActive ? "pause.fill" : "play.fill", primary: true,
                                        tooltip: session.isActive ? "Pause and release microphone" : "Start or resume reading") {
                    if session.isActive { session.pause() }
                    else { prepareToRead(); session.start() }
                }
                .accessibilityIdentifier("notchium.teleprompter.play")
                TeleprompterGlyphButton(title: "Next paragraph", symbol: "chevron.down") {
                    session.moveParagraph(forward: true)
                }
                TeleprompterGlyphButton(title: "Stop reading", symbol: "stop.fill", action: session.stop)
            }
        }
        .frame(height: ExpandedPageStyle.controlSize)
    }

    private var status: some View {
        HStack(spacing: ExpandedPageStyle.Space.sm) {
            if model.session.mode.usesMicrophone {
                Menu {
                    TeleprompterMicrophonePicker(session: model.session)
                    Button("Refresh Microphones", action: model.session.refreshInputDevices)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "mic.fill").font(.system(size: 9, weight: .semibold))
                        TeleprompterLevelMeter(level: model.session.inputLevel)
                    }
                    .foregroundStyle(ExpandedPageStyle.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Microphone: \(model.session.microphoneDescription)")
                .accessibilityLabel("Microphone input")
                .accessibilityValue("\(Int(model.session.inputLevel * 100)) percent")
                .accessibilityIdentifier("notchium.teleprompter.inputLevel")
            }
            if model.session.state == .preparing || model.session.state == .downloading {
                ProgressView().controlSize(.mini)
            }
            Text(model.session.message ?? model.session.statusText)
                .font(.system(size: 10))
                .foregroundStyle(model.session.message == nil ? ExpandedPageStyle.secondary : .white)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(model.session.message ?? model.session.statusText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(model.session.wordIndex)/\(model.session.alignment.wordCount)")
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(ExpandedPageStyle.secondary)
        }
        .frame(height: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notchium.teleprompter.status")
    }
}

/// The notch's own glyph button: bare at rest, a soft glass disc on hover (the header utilities'
/// `NotchUtilityLabel`). The primary action keeps a quiet white disc, like Music's Play/Pause.
private struct TeleprompterGlyphButton: View {
    /// Spoken label; also the tooltip unless `tooltip` is given.
    let title: String
    let symbol: String
    var primary = false
    var tooltip: String?
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @NotchReducedMotion private var reduceMotion

    var body: some View {
        Button(action: action) {
            NotchUtilityLabel(symbol: symbol, isHovered: isHovered && isEnabled, isSelected: primary,
                              foreground: primary ? .white : nil)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .onHover { isHovered = $0 }
        .help(tooltip ?? title)
        .accessibilityLabel(title)
    }
}

/// Words per minute as two glyph steps around the value; VoiceOver still sees a native stepper.
private struct TeleprompterPaceControl: View {
    @Binding var wordsPerMinute: Double
    private let range: ClosedRange<Double> = 50...300

    var body: some View {
        HStack(spacing: 0) {
            TeleprompterGlyphButton(title: "Slower", symbol: "minus") { step(-10) }
                .disabled(wordsPerMinute <= range.lowerBound)
            Text("\(Int(wordsPerMinute)) wpm")
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(ExpandedPageStyle.secondary)
                .frame(minWidth: 52)
            TeleprompterGlyphButton(title: "Faster", symbol: "plus") { step(10) }
                .disabled(wordsPerMinute >= range.upperBound)
        }
        .accessibilityRepresentation {
            Stepper("Words per minute", value: $wordsPerMinute, in: range, step: 10)
                .accessibilityValue("\(Int(wordsPerMinute)) words per minute")
        }
    }

    private func step(_ delta: Double) {
        wordsPerMinute = min(max(wordsPerMinute + delta, range.lowerBound), range.upperBound)
    }
}

/// A thin, thumbless line: how far through the script the reader is, in the page tone.
private struct TeleprompterProgressLine: View {
    let fraction: Double
    @NotchReducedMotion private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(.white.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule().fill(.tint)
                        .frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
                        .animation(NotchMotionStyle.contentChange(reduceMotion: reduceMotion), value: fraction)
                }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Script progress")
        .accessibilityValue("\(Int((min(max(fraction, 0), 1) * 100).rounded())) percent")
    }
}

/// Microphone input as a short live bar; it moves only while the microphone is listening.
private struct TeleprompterLevelMeter: View {
    let level: Double

    var body: some View {
        Capsule().fill(.white.opacity(0.15))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(.tint)
                        .frame(width: proxy.size.width * CGFloat(min(max(level, 0), 1)))
                }
            }
            .frame(width: 26, height: 3)
            .accessibilityHidden(true)
    }
}
