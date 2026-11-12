import AppKit
import NotchiumCore
import NotchiumDesignSystem
import SwiftUI

/// A cached, width-aware projection. Microphone and word updates never remeasure the script.
struct TeleprompterReaderLayout {
    static func readingInset(fontSize: Double) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        return ceil(font.ascender - font.descender + font.leading) + 5
    }

    struct Line: Identifiable {
        let id: Int
        let fragments: [TeleprompterScriptDisplay.Fragment]
        /// The first line of a paragraph; the reader leaves extra space above it.
        var startsParagraph = false

        /// One visual row. A paragraph's closing line break is spacing, not text: drawn on a
        /// single row it would otherwise truncate with an ellipsis.
        var text: Text {
            fragments.enumerated().reduce(Text(verbatim: "")) { result, item in
                let (index, fragment) = item
                let string = index == fragments.count - 1
                    ? String(fragment.text.reversed().drop(while: \.isNewline).reversed()) : fragment.text
                let part = Text(verbatim: string).customAttribute(
                    TeleprompterWordAttribute(index: fragment.wordIndex, isWord: fragment.isWord))
                return Text("\(result)\(part)")
            }
        }
    }

    static func lines(alignment: TeleprompterAlignment, width: CGFloat, fontSize: Double) -> [Line] {
        guard width.isFinite, width > 0, fontSize.isFinite, fontSize > 0 else { return [] }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)]
        var lines: [Line] = []
        var pending: [TeleprompterScriptDisplay.Fragment] = []
        var firstWord = 0
        var paragraph = -1
        var startsParagraph = false
        var lineWidth: CGFloat = 0
        for word in alignment.words {
            let fragments = TeleprompterScriptDisplay.fragments(alignment: alignment, words: word.id..<(word.id + 1))
            let wordText = fragments.map(\.text).joined()
            let wordWidth = (wordText as NSString).size(withAttributes: attributes).width
            if !pending.isEmpty, paragraph != word.paragraphIndex || lineWidth + wordWidth > width {
                lines.append(.init(id: firstWord, fragments: pending, startsParagraph: startsParagraph))
                pending = []
                lineWidth = 0
            }
            if pending.isEmpty {
                startsParagraph = paragraph != word.paragraphIndex
                firstWord = word.id
                paragraph = word.paragraphIndex
            }
            pending.append(contentsOf: fragments)
            lineWidth += wordWidth
        }
        if !pending.isEmpty { lines.append(.init(id: firstWord, fragments: pending, startsParagraph: startsParagraph)) }
        return lines
    }
}

/// The reading viewport. The script crawls continuously: the reading position glides toward the
/// latest confirmed word at the speaker's pace (`TeleprompterGlide`), and the view scrolls through
/// each line in proportion to the words read in it, so neither the underline nor the lines step.
/// Only the lines near the viewport are rendered. Reduce Motion shows progress immediately.
struct TeleprompterReadingText: View {
    let session: TeleprompterReadingSession
    @NotchReducedMotion private var reduceMotion
    @State private var lines: [TeleprompterReaderLayout.Line] = []
    @State private var glide = TeleprompterGlide.rest(at: 0, time: 0)
    @State private var pace = TeleprompterPace()
    @State private var settled = true
    @State private var hasPosition = false
    /// Look-ahead scrolling while not reading, in points; positive shows earlier lines.
    @State private var browse: CGFloat = 0

    private struct LayoutKey: Equatable {
        let text: String
        let width: CGFloat
        let fontSize: Double
    }

    var body: some View {
        GeometryReader { geometry in
            let key = LayoutKey(text: session.alignment.text, width: geometry.size.width, fontSize: session.fontSize)
            let layout = readerGeometry
            TimelineView(.animation(minimumInterval: nil, paused: settled)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                viewport(displayed: settled ? glide.target : glide.position(at: time), layout: layout,
                         height: geometry.size.height)
            }
            .overlay {
                TeleprompterReaderInput(allowsBrowsing: !session.isActive,
                    click: { y in reanchor(at: y, layout: layout, height: geometry.size.height) },
                    scroll: { delta in look(by: delta, layout: layout, height: geometry.size.height) })
            }
            .onChange(of: key, initial: true) { _, value in
                lines = TeleprompterReaderLayout.lines(alignment: session.alignment,
                    width: value.width, fontSize: value.fontSize)
                browse = 0
            }
            .onChange(of: session.isActive) { _, active in
                if active { foldLookAhead(layout: layout, height: geometry.size.height) }
            }
        }
        .clipped()
        .onChange(of: session.position, initial: true) { _, target in follow(target) }
        .onChange(of: reduceMotion) { _, _ in
            glide = .rest(at: session.position, time: Self.now)
            settled = true
        }
        .task(id: glide) {
            let remaining = glide.endTime - Self.now
            if remaining > 0 {
                do { try await Task.sleep(for: .seconds(remaining + 0.02)) } catch { return }
            }
            settled = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notchium.teleprompter.reader")
    }

    private func viewport(displayed: Double, layout: TeleprompterReaderGeometry, height: CGFloat) -> some View {
        let top = layout.viewportTop(atWord: displayed, height: height) - browse
        let range = layout.lines(from: top, to: top + height)
            .flatMap { $0.upperBound < lines.count ? $0 : nil }
        let activeIndex = min(Int(layout.map.line(atWord: displayed)), lines.count - 1)
        let activeLine = lines.indices.contains(activeIndex) ? lines[activeIndex].id : nil
        let activeBottom = activeLine == nil ? 0 : layout.tops[activeIndex] + layout.pitch - top
        let fadeStart = min(1, max(0.78, activeBottom / max(1, height)))
        return ZStack(alignment: .topLeading) {
            Color.clear
            if let range {
                ForEach(Array(lines[range].enumerated()), id: \.element.id) { offset, line in
                    Button { session.seek(to: line.id) } label: {
                        line.text
                            .font(.system(size: session.fontSize, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .textRenderer(TeleprompterWordRenderer(position: displayed,
                                                                   highlight: TeleprompterReaderStyle.marker))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(line.id == activeLine ? "notchium.teleprompter.activeLine"
                                                                   : "notchium.teleprompter.line.\(line.id)")
                    .offset(y: layout.tops[range.lowerBound + offset] - top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .mask {
            LinearGradient(stops: [.init(color: .black, location: fadeStart), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notchium.teleprompter.viewport")
    }

    // MARK: Motion

    private static var now: TimeInterval { Date.now.timeIntervalSinceReferenceDate }
    private var readerGeometry: TeleprompterReaderGeometry {
        TeleprompterReaderGeometry(lineStarts: lines.map(\.id), paragraphStarts: lines.map(\.startsParagraph),
                                   wordCount: session.alignment.wordCount,
                                   pitch: TeleprompterReaderLayout.readingInset(fontSize: session.fontSize))
    }

    private func follow(_ target: Double) {
        let now = Self.now
        guard hasPosition, !reduceMotion else {
            hasPosition = true
            glide = .rest(at: target, time: now)
            settled = true
            return
        }
        let steady = session.mode != .voiceFollow
        if steady { pace.setFixed(wordsPerMinute: session.wordsPerMinute) }
        else { pace.observe(target: target, at: now) }
        glide = glide.retargeted(to: target, at: now, pace: pace.wordsPerSecond, steady: steady)
        settled = glide.isFinished(at: now)
    }

    /// A click reanchors at the line under the pointer, gliding from what is on screen.
    private func reanchor(at y: CGFloat, layout: TeleprompterReaderGeometry, height: CGFloat) {
        let top = layout.viewportTop(atWord: glide.position(at: Self.now), height: height) - browse
        guard let index = layout.line(atY: y + top), lines.indices.contains(index) else { return }
        foldLookAhead(layout: layout, height: height)
        session.seek(to: lines[index].id)
        // Seeking to the current line changes nothing upstream; still settle on it.
        follow(session.position)
    }

    private func look(by delta: CGFloat, layout: TeleprompterReaderGeometry, height: CGFloat) {
        guard !layout.tops.isEmpty else { return }
        let reading = layout.viewportTop(atWord: glide.position(at: Self.now), height: height)
        let firstTop = layout.viewportTop(atWord: 0, height: height)
        let lastTop = layout.viewportTop(atWord: Double(layout.map.wordCount), height: height)
        browse = min(max(browse + delta, reading - lastTop), reading - firstTop)
    }

    /// Turns look-ahead scrolling into the glide's starting point, so returning to the reading
    /// position (or a clicked line) moves smoothly from what is currently on screen.
    private func foldLookAhead(layout: TeleprompterReaderGeometry, height: CGFloat) {
        guard browse != 0 else { return }
        let now = Self.now
        if reduceMotion {
            browse = 0
            glide = .rest(at: session.position, time: now)
            settled = true
            return
        }
        let visible = layout.viewportTop(atWord: glide.position(at: now), height: height) - browse
        glide = .rest(at: layout.word(atViewportTop: visible, height: height), time: now)
        browse = 0
        glide = glide.retargeted(to: session.position, at: now, pace: pace.wordsPerSecond)
        settled = glide.isFinished(at: now)
    }
}
