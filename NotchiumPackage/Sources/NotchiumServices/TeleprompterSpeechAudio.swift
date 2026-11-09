import AVFoundation
import Foundation
import Speech
import Synchronization

/// Enough bounded headroom for a brief scheduling hitch, rather than ending capture
/// after the previous eight 1024-frame packets (170 ms at 48 kHz).
enum TeleprompterAudioBuffering {
    static func packetCapacity(sampleRate: Double, framesPerPacket: Int = 1024) -> Int {
        guard sampleRate.isFinite, sampleRate > 0, framesPerPacket > 0 else { return 16 }
        return Int(min(256, max(16, ceil(sampleRate * 2 / Double(framesPerPacket)))))
    }
}

/// Metering is independent of conversion/recognition backlog. Mutex protects only a
/// tiny frame counter; no platform buffer, allocation or await occurs under the lock.
final class TeleprompterAudioLevelGate: Sendable {
    private struct State: Sendable {
        var frames: Int64 = 0
        var nextReport = 0.0
    }
    private let sampleRate: Double
    private let state = Mutex(State())

    init(sampleRate: Double) { self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 1 }

    func shouldReport(frameCount: Int) -> Bool {
        guard frameCount > 0 else { return false }
        return state.withLock { value in
            let seconds = Double(value.frames) / sampleRate
            value.frames += Int64(frameCount)
            guard seconds >= value.nextReport else { return false }
            value.nextReport = seconds + 0.04
            return true
        }
    }
}

/// A value-copy boundary out of AVAudioEngine's borrowed tap buffer. No native mutable
/// audio buffer crosses to a task or actor; the owner bounds queued audio by duration.
struct TeleprompterMicrophonePacket: Sendable {
    let samples: [[Float]]
    let frameCount: Int
    let sampleTime: Int64?
    let rms: Double

    static func copying(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) -> Self? {
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frameCount > 0, channels > 0, channels <= 8,
              buffer.format.commonFormat == .pcmFormatFloat32,
              let data = buffer.floatChannelData else { return nil }
        var samples = [[Float]]()
        samples.reserveCapacity(channels)
        var energy = 0.0
        for channel in 0..<channels {
            var values = [Float](repeating: 0, count: frameCount)
            for frame in 0..<frameCount {
                let value = buffer.format.isInterleaved ? data[0][frame * channels + channel] : data[channel][frame]
                values[frame] = value.isFinite ? value : 0
                energy += Double(values[frame]) * Double(values[frame])
            }
            samples.append(values)
        }
        return Self(samples: samples, frameCount: frameCount,
                    sampleTime: time.isSampleTimeValid ? time.sampleTime : nil,
                    rms: min(1, sqrt(energy / Double(frameCount * channels))))
    }
}

/// A dedicated actor owns the native converter and mutable buffers. Conversion and
/// allocation happen off the audio tap; only immutable AnalyzerInput leaves the actor.
actor TeleprompterSpeechAudioConverter {
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init?(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        // Some Speech runtimes trap, rather than throw, when AnalyzerInput is given
        // floating-point PCM. Restrict the baseline bridge before that initializer.
        guard Self.supportsAnalyzerRepresentation(outputFormat),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter
    }

    /// Choose only formats declared compatible by the configured speech module. Prefer
    /// 16 kHz to keep the live pipeline small, otherwise retain the negotiated rate.
    static func selectAnalyzerFormat(supported: [AVAudioFormat], negotiated: AVAudioFormat?) -> AVAudioFormat? {
        let compatible = supported.filter(supportsAnalyzerRepresentation)
        if let standard = compatible.first(where: { $0.sampleRate == 16_000 }) { return standard }
        if let negotiated, let sameRate = compatible.first(where: { $0.sampleRate == negotiated.sampleRate }) {
            return sameRate
        }
        return compatible.first
    }

    private static func supportsAnalyzerRepresentation(_ format: AVAudioFormat) -> Bool {
        format.commonFormat == .pcmFormatInt16 && format.channelCount == 1
            && format.sampleRate.isFinite && format.sampleRate > 0
    }

    func convert(_ packet: TeleprompterMicrophonePacket) throws -> AnalyzerInput? {
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(packet.frameCount)),
              let channels = input.floatChannelData,
              packet.samples.count == Int(inputFormat.channelCount) else {
            throw TeleprompterSpeechFailure.audioInputUnavailable
        }
        input.frameLength = AVAudioFrameCount(packet.frameCount)
        for channel in packet.samples.indices {
            for frame in 0..<packet.frameCount {
                if inputFormat.isInterleaved {
                    channels[0][frame * packet.samples.count + channel] = packet.samples[channel][frame]
                } else {
                    channels[channel][frame] = packet.samples[channel][frame]
                }
            }
        }
        let capacity = ceil(Double(packet.frameCount) * outputFormat.sampleRate / inputFormat.sampleRate) + 64
        guard capacity.isFinite, capacity > 0, capacity < Double(UInt32.max),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(capacity)) else {
            throw TeleprompterSpeechFailure.audioInputUnavailable
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            guard !supplied else { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, status != .error else { throw TeleprompterSpeechFailure.audioInputUnavailable }
        // Conversion can prime/buffer samples, so original packet times are not the
        // converted buffer's start time. With no dropped input, nil produces the
        // correct contiguous analyzer timeline from the converted frame counts.
        return output.frameLength > 0 ? AnalyzerInput(buffer: output) : nil
    }
}
