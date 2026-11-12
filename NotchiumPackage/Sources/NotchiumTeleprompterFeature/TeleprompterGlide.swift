import CoreGraphics
import Foundation

/// One leg of the reader's motion toward the latest confirmed word.
///
/// Speech recognition arrives in bursts. Jumping to each burst (or gliding for a fixed,
/// short time) reads as stop-start motion. A glide instead leaves at the reader's current
/// speed, travels at roughly the speaker's pace and eases to rest at the target. Chaining
/// glides at every update keeps both position and speed continuous. The curve is a cubic
/// Hermite segment whose slope never changes sign, so the reader never passes the target:
/// it never shows a word as read before recognition confirms it.
struct TeleprompterGlide: Equatable {
    var startTime: TimeInterval
    var startPosition: Double
    var target: Double
    var duration: TimeInterval
    /// The starting slope of the normalized curve (0 = start from rest). Kept within 0...3,
    /// the range in which the curve stays monotonic.
    var initialSlope: Double

    static func rest(at position: Double, time: TimeInterval) -> Self {
        Self(startTime: time, startPosition: position, target: position, duration: 0, initialSlope: 0)
    }

    var endTime: TimeInterval { startTime + duration }
    func isFinished(at time: TimeInterval) -> Bool { duration <= 0 || time >= endTime }

    func position(at time: TimeInterval) -> Double {
        guard duration > 0 else { return target }
        let u = min(max((time - startTime) / duration, 0), 1)
        let c = initialSlope
        let eased = (c - 2) * u * u * u + (3 - 2 * c) * u * u + c * u
        return startPosition + (target - startPosition) * eased
    }

    /// Words per second at `time`, signed in the direction of travel.
    func velocity(at time: TimeInterval) -> Double {
        guard duration > 0, time < endTime else { return 0 }
        let u = min(max((time - startTime) / duration, 0), 1)
        let c = initialSlope
        let slope = 3 * (c - 2) * u * u + 2 * (3 - 2 * c) * u + c
        return (target - startPosition) * slope / duration
    }

    /// Continues from wherever the reader is now toward `target`.
    /// - Parameters:
    ///   - pace: the speaker's (or fixed mode's) reading rate in words per second.
    ///   - steady: the target advances in small regular ticks (fixed speed), so track it closely;
    ///     speech arrives in uneven bursts, so ease longer to keep moving between them.
    func retargeted(to target: Double, at time: TimeInterval, pace: Double, steady: Bool = false) -> Self {
        let position = position(at: time)
        let gap = target - position
        guard abs(gap) > 0.0005 else { return .rest(at: target, time: time) }
        let velocity = velocity(at: time)
        let duration: TimeInterval
        if gap < 0 || gap > Self.reanchorWords {
            // A deliberate seek, restart or reacquisition: a brief ease, not a slow crawl.
            duration = min(0.45, 0.28 + abs(gap) * 0.003)
        } else {
            // Travel at the speaker's pace, catching up faster the further behind it is.
            // Tuned by simulation: speech bursts stay in continuous motion about 0.7 words behind
            // the latest recognized word; fixed ticks are tracked within about a quarter word.
            let speed = max(pace, gap / Self.catchUp, 0.5)
            duration = (steady ? Self.steadyEase : Self.speechEase) * gap / speed
        }
        // Leave at the current speed (continuous velocity) when it points the same way.
        let carried = velocity * gap > 0 ? velocity * duration / gap : 0
        return Self(startTime: time, startPosition: position, target: target, duration: duration,
                    initialSlope: min(max(carried, 0), 3))
    }

    /// How much longer than constant-speed travel a glide takes, leaving room to ease to rest.
    static let speechEase = 1.5
    static let steadyEase = 1.15
    /// The reader closes a gap of g words at no less than g / catchUp words per second.
    static let catchUp = 0.9
    /// Forward jumps larger than this are reacquisitions, not speech.
    static let reanchorWords = 12.0
}

/// Learns how fast this speaker is reading from how far, and how often, recognition advances.
struct TeleprompterPace: Equatable {
    private(set) var wordsPerSecond: Double
    private var lastTarget: Double?
    private var lastAdvance: TimeInterval?

    init(wordsPerSecond: Double = 140.0 / 60) {
        self.wordsPerSecond = wordsPerSecond
    }

    mutating func observe(target: Double, at time: TimeInterval) {
        defer { lastTarget = target }
        guard let previous = lastTarget else { lastAdvance = time; return }
        let advance = target - previous
        // A repeated position (a click on the current line) carries no timing information.
        guard advance != 0 else { return }
        guard advance > 0, advance <= TeleprompterGlide.reanchorWords else {
            // Seeks and reacquisitions say nothing about speaking pace.
            lastAdvance = advance > 0 ? time : nil
            return
        }
        if let lastAdvance {
            let interval = time - lastAdvance
            // Ignore near-simultaneous revisions and long silences.
            if interval > 0.08, interval < 4 {
                let measured = min(max(advance / interval, 0.8), 6)
                wordsPerSecond += (measured - wordsPerSecond) * 0.3
            }
        }
        lastAdvance = time
    }

    /// A fixed-speed mode states its pace outright.
    mutating func setFixed(wordsPerMinute: Double) {
        wordsPerSecond = min(max(wordsPerMinute / 60, 0.5), 6)
    }
}

/// Maps between word positions and a continuous line coordinate (line index plus the fraction
/// of that line's words already read), so the script crawls through each line instead of
/// stepping a whole line at a time.
struct TeleprompterLineMap: Equatable {
    /// The first word index of each line, ascending.
    let lineStarts: [Int]
    let wordCount: Int

    func line(atWord position: Double) -> Double {
        guard !lineStarts.isEmpty else { return 0 }
        let index = max(0, (lineStarts.lastIndex { Double($0) <= position } ?? 0))
        let start = Double(lineStarts[index])
        let end = Double(index + 1 < lineStarts.count ? lineStarts[index + 1] : wordCount)
        guard end > start else { return Double(index) }
        return Double(index) + min(max((position - start) / (end - start), 0), 1)
    }

    func word(atLine coordinate: Double) -> Double {
        guard !lineStarts.isEmpty else { return 0 }
        // The last line spans coordinates count - 1 ... count, like every other line.
        let clamped = min(max(coordinate, 0), Double(lineStarts.count))
        let index = min(Int(clamped.rounded(.down)), lineStarts.count - 1)
        let start = Double(lineStarts[index])
        let end = Double(index + 1 < lineStarts.count ? lineStarts[index + 1] : wordCount)
        return start + (end - start) * (clamped - Double(index))
    }
}

/// Where every line sits vertically (paragraphs get extra space above them) and how the crawl's
/// content offset relates to the reading position.
struct TeleprompterReaderGeometry: Equatable {
    let map: TeleprompterLineMap
    /// The top of each line, ascending.
    let tops: [CGFloat]
    let pitch: CGFloat

    /// Extra space above a paragraph, as a fraction of a line.
    static let paragraphSpacing: CGFloat = 0.5

    init(lineStarts: [Int], paragraphStarts: [Bool], wordCount: Int, pitch: CGFloat) {
        map = TeleprompterLineMap(lineStarts: lineStarts, wordCount: wordCount)
        self.pitch = pitch
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for index in lineStarts.indices {
            if index > 0 {
                let opensParagraph = index < paragraphStarts.count && paragraphStarts[index]
                y += pitch + (opensParagraph ? pitch * Self.paragraphSpacing : 0)
            }
            tops.append(y)
        }
        self.tops = tops
    }

    /// Move through the preceding rows while leaving the entire previous line in view.
    func viewportTop(atWord position: Double, height: CGFloat) -> CGFloat {
        viewportTop(atLine: map.line(atWord: position), height: height)
    }

    private func viewportTop(atLine coordinate: Double, height: CGFloat) -> CGFloat {
        guard !tops.isEmpty else { return 0 }
        let index = min(Int(coordinate.rounded(.down)), tops.count - 1)
        let previousTop = index > 0 ? tops[index - 1] : -pitch
        let earlierTop = index > 1 ? tops[index - 2] : -pitch
        let progress = CGFloat(coordinate - Double(index))
        let crawlTop = earlierTop + (previousTop - earlierTop) * progress
        // A large font or a paragraph gap can use up the room for a third row.
        let earliestTop = tops[index] + pitch - height
        return min(previousTop, max(crawlTop, earliestTop))
    }

    /// Recover a reading position when returning from manual scrolling.
    func word(atViewportTop top: CGFloat, height: CGFloat) -> Double {
        var lower = 0.0
        var upper = Double(tops.count)
        while upper - lower > 0.000001 {
            let middle = (lower + upper) / 2
            if viewportTop(atLine: middle, height: height) < top { lower = middle }
            else { upper = middle }
        }
        return map.word(atLine: upper)
    }

    /// The line drawn at content `y`, excluding paragraph gaps.
    func line(atY y: CGFloat) -> Int? {
        guard let index = lastLine(atOrAbove: y), y < tops[index] + pitch else { return nil }
        return index
    }

    /// Lines whose rows intersect `minY...maxY`.
    func lines(from minY: CGFloat, to maxY: CGFloat) -> ClosedRange<Int>? {
        guard !tops.isEmpty, maxY >= minY else { return nil }
        let lower = lastLine(atOrAbove: minY) ?? 0
        guard let upper = lastLine(atOrAbove: maxY), upper >= lower else { return nil }
        return lower...upper
    }

    /// Binary search: the last line whose top is at or above `y`.
    private func lastLine(atOrAbove y: CGFloat) -> Int? {
        var low = 0
        var high = tops.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if tops[middle] <= y { found = middle; low = middle + 1 } else { high = middle - 1 }
        }
        return found
    }
}
