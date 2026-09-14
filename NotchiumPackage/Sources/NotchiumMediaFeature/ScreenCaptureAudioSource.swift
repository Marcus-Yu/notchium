import ScreenCaptureKit

@MainActor
protocol SystemAudioCapturing: AnyObject {
    func start(levels: @escaping @Sendable ([CGFloat]) -> Void,
               failure: @escaping @Sendable () -> Void) async throws
    func stop() async
}

/// The OS boundary. Only an audio output is registered; no video or microphone
/// samples are consumed, rendered, or saved.
@MainActor
final class ScreenCaptureAudioSource: SystemAudioCapturing {
    private var stream: SCStream?
    private var output: SystemAudioOutput?

    func start(levels: @escaping @Sendable ([CGFloat]) -> Void,
               failure: @escaping @Sendable () -> Void) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureMicrophone = false
        configuration.width = 2; configuration.height = 2
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
        let output = SystemAudioOutput(publish: levels, onFailure: failure)
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                              configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        self.output = output; self.stream = stream
        try await stream.startCapture()
    }
    func stop() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil; output = nil
    }
    private enum CaptureError: Error { case noDisplay }
}

/// All mutable sample/FFT state is confined to the serial sampleHandlerQueue.
private final class SystemAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "Notchium.system-audio", qos: .userInitiated)
    private let analyzer = AudioSpectrumAnalyzer()
    private var pending: [[Float]] = []
    private var sampleRate: Double = 0
    private var lastEmission: CFTimeInterval = 0
    private let publish: @Sendable ([CGFloat]) -> Void
    private let onFailure: @Sendable () -> Void

    init(publish: @escaping @Sendable ([CGFloat]) -> Void, onFailure: @escaping @Sendable () -> Void) {
        self.publish = publish; self.onFailure = onFailure
    }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { onFailure() }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, buffer.isValid,
              let format = buffer.formatDescription?.audioStreamBasicDescription,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else { return }
        let channelCount = Int(format.mChannelsPerFrame)
        guard channelCount > 0, channelCount <= 2 else { return }
        if pending.count != channelCount || sampleRate != format.mSampleRate {
            pending = Array(repeating: [], count: channelCount); sampleRate = format.mSampleRate
        }
        let accepted = (try? buffer.withAudioBufferList { list, _ -> Bool in
            var channelOffset = 0
            for audioBuffer in list {
                guard let data = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { return false }
                let channels = Int(audioBuffer.mNumberChannels)
                guard channels > 0, channelOffset + channels <= channelCount else { return false }
                let samples = data.assumingMemoryBound(to: Float.self)
                let frames = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size / channels
                for channel in 0..<channels {
                    for frame in 0..<frames {
                        let value = samples[frame * channels + channel]
                        pending[channelOffset + channel].append(value.isFinite ? value : 0)
                    }
                }
                channelOffset += channels
            }
            return channelOffset == channelCount
        }) ?? false
        guard accepted else {
            pending = Array(repeating: [], count: channelCount)
            return
        }
        let count = AudioSpectrumAnalyzer.sampleCount
        guard pending.allSatisfy({ $0.count >= count }) else { return }
        // Bound both retained PCM and main-actor publications, even with bursty delivery.
        pending = pending.map { Array($0.suffix(count)) }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastEmission >= 1.0 / 30 else { return }
        lastEmission = now
        publish(analyzer.levels(channels: pending, sampleRate: sampleRate))
    }
}
