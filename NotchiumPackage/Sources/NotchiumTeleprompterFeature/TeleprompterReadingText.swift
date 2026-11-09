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

        var text: Text {
            fragments.reduce(Text(verbatim: "")) { result, fragment in
                let part = Text(verbatim: fragment.text).customAttribute(
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
        var lineWidth: CGFloat = 0
        for word in alignment.words {
            let fragments = TeleprompterScriptDisplay.fragments(alignment: alignment, words: word.id..<(word.id + 1))
            let wordText = fragments.map(\.text).joined()
            let wordWidth = (wordText as NSString).size(withAttributes: attributes).width
            if !pending.isEmpty, paragraph != word.paragraphIndex || lineWidth + wordWidth > width {
                lines.append(.init(id: firstWord, fragments: pending))
                pending = []
                lineWidth = 0
            }
            if pending.isEmpty { firstWord = word.id; paragraph = word.paragraphIndex }
            pending.append(contentsOf: fragments)
            lineWidth += wordWidth
        }
        if !pending.isEmpty { lines.append(.init(id: firstWord, fragments: pending)) }
        return lines
    }
}

struct TeleprompterReadingText: View {
    let session: TeleprompterReadingSession
    @NotchReducedMotion private var reduceMotion
    @State private var lines: [TeleprompterReaderLayout.Line] = []
    @State private var reflowRevision = 0
    @State private var lineHeights: [Int: CGFloat] = [:]

    private struct LayoutKey: Equatable {
        let text: String
        let width: CGFloat
        let fontSize: Double
    }

    private struct FollowTarget: Equatable {
        let line: Int
        let reflowRevision: Int
        let height: CGFloat
    }

    var body: some View {
        GeometryReader { geometry in
            let key = LayoutKey(text: session.alignment.text, width: geometry.size.width, fontSize: session.fontSize)
            let active = lines.last(where: { $0.id <= session.wordIndex })?.id ?? 0
            let inset = TeleprompterReaderLayout.readingInset(fontSize: session.fontSize)
            let activeHeight = lineHeights[active] ?? (inset - 5)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(lines) { line in
                            Button { session.seek(to: line.id) } label: {
                                line.text
                                    .font(.system(size: session.fontSize, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineSpacing(2)
                                    .textRenderer(TeleprompterWordRenderer(position: session.position,
                                                                           highlight: TeleprompterReaderStyle.marker))
                                    .animation(reduceMotion ? nil : TeleprompterReaderStyle.wordFollow, value: session.position)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .help("Read from this line")
                            .accessibilityIdentifier(line.id == active ? "notchium.teleprompter.activeLine" : "notchium.teleprompter.line.\(line.id)")
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                                lineHeights[line.id] = height
                            }
                            .id(line.id)
                        }
                    }
                    .padding(.top, inset)
                    .padding(.bottom, max(48, geometry.size.height - inset))
                }
                .scrollIndicators(.hidden)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("notchium.teleprompter.viewport")
                .onChange(of: FollowTarget(line: active, reflowRevision: reflowRevision, height: activeHeight)) { old, target in
                    let animate = !reduceMotion && old.reflowRevision == target.reflowRevision && old.line != target.line
                    // scrollTo aligns the same fractional point in the target and
                    // viewport. Account for the target's actual height, including wrapping.
                    let difference = geometry.size.height - target.height
                    let readingAnchor = UnitPoint(x: 0, y: abs(difference) > 1 ? inset / difference : 0)
                    withAnimation(animate ? TeleprompterReaderStyle.lineFollow : nil) {
                        proxy.scrollTo(target.line, anchor: readingAnchor)
                    }
                }
                .onChange(of: key, initial: true) { _, value in
                    lines = TeleprompterReaderLayout.lines(alignment: session.alignment,
                        width: value.width, fontSize: value.fontSize)
                    lineHeights.removeAll()
                    // Even unchanged line IDs may have different heights after reflow.
                    reflowRevision &+= 1
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notchium.teleprompter.reader")
    }
}
