import XCTest
@testable import NotchiumTeleprompterFeature

/// The reader's motion model: smooth, pace-matched, and never ahead of recognized speech.
final class TeleprompterGlideTests: XCTestCase {
    private let frame = 1.0 / 120

    /// Feeds recognition updates (time → confirmed word) and samples every display frame.
    private func simulate(_ updates: [(TimeInterval, Double)], until end: TimeInterval,
                          fixedWordsPerMinute: Double? = nil)
        -> [(time: TimeInterval, position: Double, target: Double)] {
        var glide = TeleprompterGlide.rest(at: 0, time: 0)
        var pace = TeleprompterPace()
        var pending = updates
        var target = 0.0
        var samples: [(TimeInterval, Double, Double)] = []
        var time = 0.0
        while time <= end {
            while let next = pending.first, next.0 <= time {
                pending.removeFirst()
                target = next.1
                if let fixedWordsPerMinute { pace.setFixed(wordsPerMinute: fixedWordsPerMinute) }
                else { pace.observe(target: target, at: next.0) }
                glide = glide.retargeted(to: target, at: next.0, pace: pace.wordsPerSecond,
                                         steady: fixedWordsPerMinute != nil)
            }
            samples.append((time, glide.position(at: time), target))
            time += frame
        }
        return samples
    }

    func testReaderNeverPassesTheLatestRecognizedWordAndNeverMovesBackward() {
        let samples = simulate([(0.0, 3), (0.7, 5), (1.3, 8), (2.1, 10), (2.4, 11)], until: 5)
        for (index, sample) in samples.enumerated() {
            XCTAssertLessThanOrEqual(sample.position, sample.target + 1e-9, "Ahead of recognition at \(sample.time)s")
            if index > 0 { XCTAssertGreaterThanOrEqual(sample.position, samples[index - 1].position - 1e-9) }
        }
        XCTAssertEqual(samples.last?.position ?? 0, 11, accuracy: 1e-6, "Settles exactly on the last word")
    }

    func testRecognitionBurstsBecomeContinuousMotionAtTheSpeakersPace() {
        // Two words every 0.8 s (2.5 words/s), arriving as bursts, for eight seconds.
        let updates = (1...10).map { (Double($0) * 0.8, Double($0) * 2) }
        let samples = simulate(updates, until: 8)
        let steady = samples.filter { $0.time > 2.4 && $0.time < 7.9 }
        let speeds = zip(steady, steady.dropFirst()).map { ($1.position - $0.position) / frame }
        XCTAssertGreaterThan(speeds.min() ?? 0, 0.5, "The reader keeps moving between bursts instead of stopping")
        XCTAssertLessThan((speeds.max() ?? 0) / max(speeds.min() ?? 1, 0.001), 6, "Speed changes stay gentle")
        XCTAssertLessThan(steady.map { $0.target - $0.position }.max() ?? 99, 3, "Lags at most a short phrase")
    }

    func testRetargetingKeepsSpeedContinuous() {
        var glide = TeleprompterGlide.rest(at: 0, time: 0).retargeted(to: 4, at: 0, pace: 2.5)
        for (time, target) in [(0.6, 6.0), (1.1, 8.0), (1.7, 10.0)] {
            let before = glide.velocity(at: time)
            glide = glide.retargeted(to: target, at: time, pace: 2.5)
            XCTAssertEqual(glide.velocity(at: time), before, accuracy: 1e-6, "Speed jumps at \(time)s")
        }
    }

    func testSeeksAndReacquisitionsEaseBrieflyAndDoNotTeachPace() {
        var pace = TeleprompterPace()
        let original = pace.wordsPerSecond
        for (from, to) in [(40.0, 0.0), (0.0, 30.0)] {
            pace.observe(target: from, at: 1)
            pace.observe(target: to, at: 1.2)
            let glide = TeleprompterGlide.rest(at: from, time: 0).retargeted(to: to, at: 0, pace: pace.wordsPerSecond)
            XCTAssertLessThanOrEqual(glide.duration, 0.45)
            XCTAssertEqual(glide.position(at: glide.duration), to, accuracy: 1e-9)
        }
        XCTAssertEqual(pace.wordsPerSecond, original, "Jumps are not speech")
    }

    func testPaceLearnsFromRecognitionCadence() {
        var pace = TeleprompterPace(wordsPerSecond: 2)
        for step in 0...20 { pace.observe(target: Double(step) * 2, at: Double(step) * 0.5) }
        XCTAssertEqual(pace.wordsPerSecond, 4, accuracy: 0.2)
        pace.observe(target: 40, at: 10.5)  // a repeated position carries no timing information
        XCTAssertEqual(pace.wordsPerSecond, 4, accuracy: 0.2)
        pace.setFixed(wordsPerMinute: 150)
        XCTAssertEqual(pace.wordsPerSecond, 2.5, accuracy: 1e-9)
    }

    func testFixedPaceTicksCrawlSteadily() {
        // Fixed speed advances the session every 100 ms; the reader should glide, not tick.
        let updates = (1...40).map { (Double($0) * 0.1, Double($0) * 0.25) }
        let samples = simulate(updates, until: 4, fixedWordsPerMinute: 150)
        let steady = samples.filter { $0.time > 1 && $0.time < 3.95 }
        let speeds = zip(steady, steady.dropFirst()).map { ($1.position - $0.position) / frame }
        XCTAssertGreaterThan(speeds.min() ?? 0, 1.0)
        XCTAssertLessThan(speeds.max() ?? 99, 4.5)
        XCTAssertLessThan(steady.map { $0.target - $0.position }.max() ?? 99, 0.4, "Within about a quarter word")
    }

    func testGeometrySpacesParagraphsAndCrawlsWhileKeepingThePreviousLineVisible() {
        // Lines start at words 0, 5, 12 (new paragraph) and 20; 30 pt pitch.
        let layout = TeleprompterReaderGeometry(lineStarts: [0, 5, 12, 20], paragraphStarts: [true, false, true, false],
                                                wordCount: 24, pitch: 30)
        XCTAssertEqual(layout.tops, [0, 30, 75, 105], "Half a line above each new paragraph")
        let height: CGFloat = 150
        XCTAssertEqual(layout.viewportTop(atWord: 2.5, height: height), -30)
        XCTAssertEqual(layout.viewportTop(atWord: 8.5, height: height), -15, accuracy: 1e-9)
        var previous = -CGFloat.infinity
        for word in stride(from: 0.0, through: 24, by: 0.25) {
            let top = layout.viewportTop(atWord: word, height: height)
            let index = min(Int(layout.map.line(atWord: word)), layout.tops.count - 1)
            XCTAssertGreaterThanOrEqual(top, previous, "Never scrolls backward while reading forward")
            if index > 0 { XCTAssertLessThanOrEqual(top, layout.tops[index - 1]) }
            let restored = layout.word(atViewportTop: top, height: height)
            XCTAssertEqual(layout.viewportTop(atWord: restored, height: height), top, accuracy: 0.001)
            previous = top
        }
        XCTAssertEqual(layout.line(atY: 10), 0)
        XCTAssertEqual(layout.line(atY: 80), 2)
        XCTAssertNil(layout.line(atY: 65), "A click in a paragraph gap reanchors nowhere")
        XCTAssertEqual(layout.lines(from: 20, to: 80), 0...2)
        XCTAssertNil(TeleprompterReaderGeometry(lineStarts: [], paragraphStarts: [], wordCount: 0, pitch: 30)
            .lines(from: 0, to: 100))
    }

    func testLargeTextKeepsThePreviousAndActiveLinesFullyInViewAcrossParagraphs() {
        let pitch: CGFloat = 53
        let height: CGFloat = 150
        let layout = TeleprompterReaderGeometry(lineStarts: [0, 4, 8, 12], paragraphStarts: [true, true, true, false],
                                                wordCount: 16, pitch: pitch)
        for word in stride(from: 0.0, through: 16, by: 0.125) {
            let index = min(Int(layout.map.line(atWord: word)), layout.tops.count - 1)
            let top = layout.viewportTop(atWord: word, height: height)
            if index > 0 { XCTAssertLessThanOrEqual(top, layout.tops[index - 1], "Previous line clipped at word \(word)") }
            XCTAssertGreaterThanOrEqual(top + height, layout.tops[index] + pitch, "Active line clipped at word \(word)")
        }
    }

    func testLineMapCrawlsThroughEachLineAndRoundTrips() {
        let map = TeleprompterLineMap(lineStarts: [0, 5, 12, 20], wordCount: 24)
        XCTAssertEqual(map.line(atWord: 0), 0)
        XCTAssertEqual(map.line(atWord: 2.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(map.line(atWord: 12), 2, accuracy: 1e-9)
        XCTAssertEqual(map.line(atWord: 24), 4, accuracy: 1e-9, "The final line ends one pitch below its start")
        for word in stride(from: 0.0, through: 24, by: 0.5) {
            XCTAssertEqual(map.word(atLine: map.line(atWord: word)), word, accuracy: 1e-9)
        }
        XCTAssertEqual(map.word(atLine: -3), 0)
        XCTAssertEqual(TeleprompterLineMap(lineStarts: [], wordCount: 0).line(atWord: 5), 0)
    }
}
