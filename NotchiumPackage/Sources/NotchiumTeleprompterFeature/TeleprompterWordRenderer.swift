import SwiftUI

struct TeleprompterWordAttribute: TextAttribute {
    let index: Int
    let isWord: Bool
}

/// Animate only drawing over a stable native text layout. Retargeting speech updates
/// start at the current presentation instead of replacing/reflowing the Text view.
@Animatable
struct TeleprompterWordRenderer: TextRenderer {
    var position: Double
    /// The reading marker's color (the Teleprompter page hue); never interpolated.
    @AnimatableIgnored var highlight: Color = .white

    var displayPadding: EdgeInsets { EdgeInsets(top: 0, leading: 0, bottom: 2, trailing: 0) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var wordBounds: [Int: [CGRect]] = [:]
        for line in layout {
            for run in line {
                guard let word = run[TeleprompterWordAttribute.self] else { context.draw(run); continue }
                var ink = context
                let consumed = min(1, max(0, position - Double(word.index)))
                ink.opacity *= 1 - 0.6 * consumed
                ink.draw(run)
                if word.isWord {
                    let rect = run.typographicBounds.rect
                    var bounds = wordBounds[word.index] ?? []
                    if let last = bounds.last, abs(last.midY - rect.midY) < 1 {
                        bounds[bounds.count - 1] = last.union(rect)
                    } else { bounds.append(rect) }
                    wordBounds[word.index] = bounds
                }
            }
        }
        let index = Int(position.rounded(.down))
        let fraction = position - Double(index)
        let currentBounds = wordBounds[index] ?? []
        let nextBounds = wordBounds[index + 1] ?? []
        if currentBounds.count == 1, nextBounds.count == 1,
           let current = currentBounds.first, let next = nextBounds.first, abs(current.midY - next.midY) < 1 {
            let rect = CGRect(x: current.minX + (next.minX - current.minX) * fraction,
                y: current.maxY + (next.maxY - current.maxY) * fraction,
                width: current.width + (next.width - current.width) * fraction, height: 1.5)
            underline(rect, opacity: 1, in: &context)
        } else {
            for current in currentBounds {
                underline(CGRect(x: current.minX, y: current.maxY, width: current.width, height: 1.5),
                          opacity: 1 - fraction, in: &context)
            }
            for next in nextBounds {
                underline(CGRect(x: next.minX, y: next.maxY, width: next.width, height: 1.5),
                          opacity: fraction, in: &context)
            }
        }
    }

    private func underline(_ rect: CGRect, opacity: Double, in context: inout GraphicsContext) {
        var ink = context
        ink.opacity *= opacity
        ink.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(highlight))
    }
}
