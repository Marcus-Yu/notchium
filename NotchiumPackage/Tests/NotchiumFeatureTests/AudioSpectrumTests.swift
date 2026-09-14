import XCTest
@testable import NotchiumMediaFeature

final class AudioSpectrumTests: XCTestCase {
    func testSevenBandsDistinguishPCMTonesIncludingOppositePhaseStereo() {
        for (index, frequency) in [90.0, 180, 360, 720, 1440, 3200, 8000].enumerated() {
            let analyzer = AudioSpectrumAnalyzer()
            let samples = (0..<AudioSpectrumAnalyzer.sampleCount).map {
                Float(0.5 * sin(2 * Double.pi * frequency * Double($0) / 48_000))
            }
            let levels = analyzer.levels(channels: [samples, samples.map { -$0 }], sampleRate: 48_000)
            XCTAssertEqual(levels.count, 7)
            XCTAssertTrue(levels.allSatisfy { $0 >= 0.12 && $0 <= 1 })
            XCTAssertEqual(levels.firstIndex(of: levels.max()!), index)
        }
    }
    func testSilenceAndSlowerRelease() {
        let analyzer = AudioSpectrumAnalyzer()
        let silence = [Float](repeating: 0, count: AudioSpectrumAnalyzer.sampleCount)
        XCTAssertEqual(analyzer.levels(channels: [silence], sampleRate: 48_000), Array(repeating: 0.12, count: 7))
        let tone = (0..<AudioSpectrumAnalyzer.sampleCount).map { Float(sin(2 * Double.pi * 720 * Double($0) / 48_000)) }
        let attack = analyzer.levels(channels: [tone], sampleRate: 48_000)[3]
        let release = analyzer.levels(channels: [silence], sampleRate: 48_000)[3]
        XCTAssertGreaterThan(attack, release)
        XCTAssertGreaterThan(release, 0.12)
        XCTAssertLessThan(attack - release, attack - 0.12)
    }
    @MainActor func testPermissionDeniedNeverStartsCaptureOrMovesBars() async {
        var checks = 0
        let meter = SystemAudioMeter(capture: TestAudioCapture(), permissionGranted: { checks += 1; return false })
        meter.setPlaying(true)
        for _ in 0..<20 { await Task.yield() }
        for _ in 0..<10 { meter.setPlaying(true) }
        XCTAssertGreaterThanOrEqual(checks, 1)
        XCTAssertEqual(meter.status, .permissionRequired)
        XCTAssertEqual(meter.waveformLevels, SystemAudioMeter.staticLevels)
        meter.stop()
    }
    @MainActor func testUnavailableMeterIsStaticAndPauseImmediatelySettles() async {
        let meter = SystemAudioMeter(captureEnabled: false)
        meter.setPlaying(true)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(meter.status, .unavailable)
        XCTAssertEqual(meter.waveformLevels, SystemAudioMeter.staticLevels)
        meter.setPlaying(false)
        XCTAssertEqual(meter.waveformLevels, SystemAudioMeter.staticLevels)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(meter.waveformLevels, SystemAudioMeter.staticLevels)
        meter.stop()
    }
}
