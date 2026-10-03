import AVFAudio
import XCTest
@testable import NotchiumFocusFeature

final class PomodoroSoundTests: XCTestCase {
    func testBoostedSoundRendersThroughThePlaybackEngine() throws {
        let buffer = try PomodoroAlertAudio.buffer(named: "Ping")
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        engine.mainMixerNode.outputVolume = 1
        player.volume = 1
        // Offline mode validates decoding and playback without emitting an audible alert.
        try engine.enableManualRenderingMode(.offline, format: buffer.format, maximumFrameCount: 4096)
        defer { player.stop(); engine.stop() }
        try engine.start()
        player.scheduleBuffer(buffer)
        player.play()
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: 4096))
        XCTAssertEqual(try engine.renderOffline(4096, to: output), .success)
        let rendered = try level(output)
        XCTAssertGreaterThan(rendered.rms, 0.01)
        XCTAssertLessThanOrEqual(rendered.peak, 0.99)
    }

    func testGainBoostsQuietSamplesAndLimitsPeaksOnEveryChannel() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 7))
        let channels = try XCTUnwrap(buffer.floatChannelData)
        let samples: [Float] = [-1, -0.5, -0.1, 0, 0.1, 0.5, 1]
        buffer.frameLength = 7
        for channel in 0..<2 {
            for frame in samples.indices { channels[channel][frame] = samples[frame] }
        }

        PomodoroAlertAudio.amplify(buffer)

        for channel in 0..<2 {
            XCTAssertEqual(channels[channel][3], 0, "Silence must remain silent")
            XCTAssertGreaterThan(channels[channel][4], 0.65, "Quiet samples need a stronger boost than the previous 4× gain")
            XCTAssertLessThan(channels[channel][2], -0.65)
            for frame in samples.indices {
                XCTAssertTrue(channels[channel][frame].isFinite)
                XCTAssertLessThanOrEqual(abs(channels[channel][frame]), 0.99)
                XCTAssertEqual(channels[channel][frame], -channels[channel][6 - frame], accuracy: 0.00001)
            }
        }
        XCTAssertEqual(buffer.frameLength, 7)
    }

    func testEverySelectedSystemSoundHasHigherAverageLevelWithoutClipping() throws {
        for sound in PomodoroSound.allCases where sound != .none {
            let name = try XCTUnwrap(sound.systemName)
            let url = URL(fileURLWithPath: "/System/Library/Sounds")
                .appendingPathComponent(name).appendingPathExtension("aiff")
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let original = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                         frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: original)
            let amplified = try PomodoroAlertAudio.buffer(named: name)
            XCTAssertGreaterThanOrEqual(amplified.frameLength, original.frameLength)
            let duration = Double(amplified.frameLength) / amplified.format.sampleRate
            XCTAssertGreaterThanOrEqual(duration, 3, sound.title)
            XCTAssertLessThan(duration, max(3, Double(original.frameLength) / original.format.sampleRate) +
                              Double(original.frameLength) / original.format.sampleRate + 0.18, sound.title)
            XCTAssertEqual(amplified.format, original.format)
            let before = try level(original)
            // Compare the first complete ring, excluding the silent gaps between repetitions.
            let after = try level(amplified, frames: Int(original.frameLength))
            XCTAssertGreaterThan(after.rms, before.rms * 1.2, sound.title)
            let previous = try XCTUnwrap(original.floatChannelData)
            for channel in 0..<Int(original.format.channelCount) {
                for frame in 0..<Int(original.frameLength) {
                    previous[channel][frame] = 0.98 * tanh(previous[channel][frame] * 4)
                }
            }
            XCTAssertGreaterThan(after.rms, try level(original).rms, "Must be louder than the previous alert: \(sound.title)")
            XCTAssertLessThanOrEqual(try level(amplified).peak, 0.99, sound.title)
        }
    }

    func testExtensionRepeatsBothChannelsWithSilentGapsAndPreservesLongSounds() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 1000, channels: 2))
        let short = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 400))
        short.frameLength = 400
        let source = try XCTUnwrap(short.floatChannelData)
        for channel in 0..<2 {
            for frame in 0..<400 { source[channel][frame] = channel == 0 ? 0.5 : -0.25 }
        }
        let extended = try PomodoroAlertAudio.extend(short)
        XCTAssertEqual(extended.frameLength, 3300, "Six complete rings with five 180 ms gaps")
        let output = try XCTUnwrap(extended.floatChannelData)
        for channel in 0..<2 {
            for repetition in 0..<6 {
                let offset = repetition * 580
                for frame in 0..<400 { XCTAssertEqual(output[channel][offset + frame], source[channel][frame]) }
                if repetition < 5 {
                    for frame in 400..<580 { XCTAssertEqual(output[channel][offset + frame], 0) }
                }
            }
        }
        let long = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4000))
        long.frameLength = 4000
        XCTAssertTrue(try PomodoroAlertAudio.extend(long) === long)
        let empty = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        XCTAssertTrue(try PomodoroAlertAudio.extend(empty) === empty)
    }

    private func level(_ buffer: AVAudioPCMBuffer, frames: Int? = nil) throws -> (rms: Float, peak: Float) {
        let channels = try XCTUnwrap(buffer.floatChannelData)
        let frames = frames ?? Int(buffer.frameLength)
        var sum: Double = 0
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<frames {
                let sample = channels[channel][frame]
                XCTAssertTrue(sample.isFinite)
                sum += Double(sample) * Double(sample)
                peak = max(peak, abs(sample))
            }
        }
        return (Float(sqrt(sum / Double(frames * Int(buffer.format.channelCount)))), peak)
    }
}
