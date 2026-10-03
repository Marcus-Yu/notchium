import AppKit
import AVFAudio

/// Native macOS alerts covering the common chime, bell and digital timer styles.
public enum PomodoroSound: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, glass, ping, tink, morse, hero

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .glass: "Chime (Glass)"
        case .ping: "Bell (Ping)"
        case .tink: "Soft Tap (Tink)"
        case .morse: "Digital (Morse)"
        case .hero: "Celebration (Hero)"
        }
    }

    var systemName: NSSound.Name? {
        switch self {
        case .none: nil
        case .glass: "Glass"
        case .ping: "Ping"
        case .tink: "Tink"
        case .morse: "Morse"
        case .hero: "Hero"
        }
    }
}

@MainActor public protocol PomodoroSoundPlaying: AnyObject {
    func play(_ sound: PomodoroSound)
    func stop()
}

/// Keeps previews and completion alerts from overlapping. No audio leaves this Mac.
@MainActor public final class SystemPomodoroSoundPlayer: PomodoroSoundPlaying {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var fallback: NSSound?
    private var playbackRevision = 0

    public init() {}

    public func play(_ sound: PomodoroSound) {
        stop()
        guard let name = sound.systemName else { return }
        do {
            let buffer = try PomodoroAlertAudio.buffer(named: name)
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            engine.mainMixerNode.outputVolume = 1
            player.volume = 1
            self.engine = engine
            self.player = player
            try engine.start()
            let revision = playbackRevision
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.playbackRevision == revision else { return }
                    self.stop()
                }
            }
            player.play()
        } catch {
            stop()
            // Preserve an alert if the output device or system sound file is unavailable.
            fallback = NSSound(named: name)?.copy() as? NSSound
            fallback?.volume = 1
            fallback?.play()
        }
    }

    public func stop() {
        playbackRevision += 1
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        fallback?.stop()
        fallback = nil
    }
}

/// Boosts the short, trusted macOS recordings in memory, with smooth peak limiting.
enum PomodoroAlertAudio {
    static func buffer(named name: NSSound.Name) throws -> AVAudioPCMBuffer {
        let url = URL(fileURLWithPath: "/System/Library/Sounds")
            .appendingPathComponent(name).appendingPathExtension("aiff")
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0, file.length <= AVAudioFramePosition(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        amplify(buffer)
        return try extend(buffer)
    }

    static func amplify(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                // +18 dB input gain lifts the decay as well as the attack, with smooth peak limiting.
                channels[channel][frame] = 0.99 * tanh(channels[channel][frame] * 8)
            }
        }
    }

    static func extend(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return buffer }
        let gap = Int(buffer.format.sampleRate * 0.18)
        let minimumFrames = Int(ceil(buffer.format.sampleRate * 3))
        let repeats = max(1, Int(ceil(Double(minimumFrames + gap) / Double(frames + gap))))
        guard repeats > 1 else { return buffer }
        let totalFrames = frames * repeats + gap * (repeats - 1)
        guard totalFrames <= Int(UInt32.max),
              let extended = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                               frameCapacity: AVAudioFrameCount(totalFrames)),
              let source = buffer.floatChannelData,
              let destination = extended.floatChannelData else {
            throw CocoaError(.fileReadCorruptFile)
        }
        extended.frameLength = AVAudioFrameCount(totalFrames)
        for channel in 0..<Int(buffer.format.channelCount) {
            // Explicit silence between rings; never add a trailing gap.
            for frame in 0..<totalFrames { destination[channel][frame] = 0 }
            for repetition in 0..<repeats {
                let offset = repetition * (frames + gap)
                for frame in 0..<frames { destination[channel][offset + frame] = source[channel][frame] }
            }
        }
        return extended
    }
}
