import CoreAudio
import CoreGraphics
import Foundation

/// Spotify-only capture source. It remains active while requested even when Spotify is not
/// running, so the NSWorkspace lifecycle observer can attach when Spotify launches later.
@MainActor
final class SpotifyAudioTap: SystemAudioCapturing {
    private let processFinder: SpotifyProcessFinder
    private var tap: CoreAudioProcessTap?
    private var publish: (@Sendable ([CGFloat]) -> Void)?
    private var failure: (@Sendable () -> Void)?
    private var started = false

    init(processFinder: SpotifyProcessFinder = SpotifyProcessFinder()) {
        self.processFinder = processFinder
    }

    func start(levels: @escaping @Sendable ([CGFloat]) -> Void,
               failure: @escaping @Sendable () -> Void) async throws {
        guard !started else { return }
        started = true
        publish = levels
        self.failure = failure

        let processIdentifier = processFinder.start { [weak self] processIdentifier in
            self?.spotifyProcessChanged(to: processIdentifier)
        }
        guard let processIdentifier else {
            NSLog("[SpotifyAudioTap] Waiting for Spotify to launch")
            return
        }

        do {
            try attach(to: processIdentifier)
        } catch {
            stopResources()
            throw error
        }
    }

    func stop() async {
        guard started else { return }
        stopResources()
        NSLog("[SpotifyAudioTap] Tap stopped")
    }

    private func spotifyProcessChanged(to processIdentifier: pid_t?) {
        guard started else { return }
        tap?.stop()
        tap = nil
        guard let processIdentifier else { return }
        do {
            try attach(to: processIdentifier)
        } catch {
            log(error, operation: "Reconnect")
            failure?()
        }
    }

    private func attach(to processIdentifier: pid_t) throws {
        guard tap == nil, let publish else { return }
        let tap = CoreAudioProcessTap(publish: publish)
        do {
            try tap.start(processIdentifier: processIdentifier)
            self.tap = tap
        } catch {
            tap.stop()
            log(error, operation: "Create Spotify process tap")
            throw error
        }
    }

    private func stopResources() {
        started = false
        processFinder.stop()
        tap?.stop()
        tap = nil
        publish = nil
        failure = nil
    }

    private func log(_ error: any Error, operation: String) {
        NSLog("[SpotifyAudioTap] %@ failed: %@", operation, String(describing: error))
    }

    deinit {
        tap?.stop()
    }
}

/// Owns every HAL object in creation order and destroys them in reverse order.
private final class CoreAudioProcessTap: @unchecked Sendable {
    private let analyzer: SpotifyPCMAnalyzer
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var deviceStarted = false

    init(publish: @escaping @Sendable ([CGFloat]) -> Void) {
        analyzer = SpotifyPCMAnalyzer(publish: publish)
    }

    func start(processIdentifier: pid_t) throws {
        guard tapID == kAudioObjectUnknown else { return }
        let targets = try Self.processTargets(for: processIdentifier)
        for processObjectID in targets.objectIDs {
            NSLog("[SpotifyAudioTap] Core Audio process object found: %u", processObjectID)
        }
        if targets.objectIDs.isEmpty {
            NSLog("[SpotifyAudioTap] Spotify has not registered audio yet; tap will restore by bundle ID")
        }

        let description = CATapDescription(stereoMixdownOfProcesses: targets.objectIDs)
        description.name = "Notchium Spotify Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.isProcessRestoreEnabled = true
        description.bundleIDs = targets.bundleIDs

        try Self.check(AudioHardwareCreateProcessTap(description, &tapID), operation: "AudioHardwareCreateProcessTap")
        NSLog("[SpotifyAudioTap] Process tap created: %u", tapID)

        do {
            let format = try Self.tapFormat(tapID)
            analyzer.configure(format: format)
            NSLog("[SpotifyAudioTap] Receiving audio: %.0f Hz, %u channels", format.mSampleRate, format.mChannelsPerFrame)

            let aggregateUID = "com.marcusyu.notchium.spotify-tap.\(UUID().uuidString)"
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Notchium Spotify Tap",
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary,
                                                               &aggregateDeviceID),
                           operation: "AudioHardwareCreateAggregateDevice")
            NSLog("[SpotifyAudioTap] Aggregate device created: %u", aggregateDeviceID)

            let analyzer = analyzer
            try Self.check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, nil) {
                _, inputData, _, _, _ in
                analyzer.enqueue(inputData)
            }, operation: "AudioDeviceCreateIOProcIDWithBlock")
            guard let ioProcID else { throw SystemAudioCaptureError.coreAudio(operation: "IOProc result", status: -1) }
            try Self.check(AudioDeviceStart(aggregateDeviceID, ioProcID), operation: "AudioDeviceStart")
            deviceStarted = true
            NSLog("[SpotifyAudioTap] IOProc started")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if deviceStarted, aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            Self.logStatus(AudioDeviceStop(aggregateDeviceID, ioProcID), operation: "AudioDeviceStop")
        }
        deviceStarted = false
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            Self.logStatus(AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID), operation: "AudioDeviceDestroyIOProcID")
        }
        self.ioProcID = nil
        if aggregateDeviceID != kAudioObjectUnknown {
            Self.logStatus(AudioHardwareDestroyAggregateDevice(aggregateDeviceID), operation: "AudioHardwareDestroyAggregateDevice")
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            Self.logStatus(AudioHardwareDestroyProcessTap(tapID), operation: "AudioHardwareDestroyProcessTap")
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        analyzer.reset()
    }

    deinit { stop() }

    private static func processTargets(for processIdentifier: pid_t) throws -> (objectIDs: [AudioObjectID], bundleIDs: [String]) {
        var objectIDs: [AudioObjectID] = []
        var bundleIDs = Set([SpotifyProcessFinder.bundleIdentifier])
        for process in try AudioHardwareSystem.shared.processes {
            let pid = try? process.pid
            let bundleID = try? process.bundleID
            guard pid == processIdentifier || bundleID?.hasPrefix(SpotifyProcessFinder.bundleIdentifier) == true else {
                continue
            }
            objectIDs.append(process.id)
            if let bundleID { bundleIDs.insert(bundleID) }
        }
        return (objectIDs, bundleIDs.sorted())
    }

    private static func tapFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format),
                  operation: "Read process tap format")
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mSampleRate > 0, format.mChannelsPerFrame > 0 else {
            throw SystemAudioCaptureError.unsupportedFormat
        }
        return format
    }

    private static func check(_ status: OSStatus, operation: String) throws {
        guard status != noErr else { return }
        if status == kAudioDevicePermissionsError || status == OSStatus(0x7065726D) {
            throw SystemAudioCaptureError.permissionDenied
        }
        throw SystemAudioCaptureError.coreAudio(operation: operation, status: status)
    }

    private static func logStatus(_ status: OSStatus, operation: String) {
        guard status != noErr else { return }
        NSLog("[SpotifyAudioTap] %@ cleanup failed: OSStatus %d", operation, status)
    }
}

private struct CapturedPCM: Sendable {
    struct Buffer: Sendable {
        let data: Data
        let channelCount: Int
    }

    let buffers: [Buffer]
}

/// The IOProc only copies its transient buffers. Format conversion, accumulation, FFT, smoothing,
/// and publication all happen on this serial processing queue.
private final class SpotifyPCMAnalyzer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Notchium.spotify-audio-analysis", qos: .userInitiated)
    private let spectrum = AudioSpectrumAnalyzer()
    private let publish: @Sendable ([CGFloat]) -> Void
    private var format = AudioStreamBasicDescription()
    private var pending: [[Float]] = []
    private var lastEmission: CFTimeInterval = 0
    private var didLogUnsupportedFormat = false

    init(publish: @escaping @Sendable ([CGFloat]) -> Void) {
        self.publish = publish
    }

    func configure(format: AudioStreamBasicDescription) {
        queue.sync {
            self.format = format
            pending = Array(repeating: [], count: Int(format.mChannelsPerFrame))
        }
    }

    func enqueue(_ inputData: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData)).compactMap { buffer -> CapturedPCM.Buffer? in
            guard let bytes = buffer.mData, buffer.mDataByteSize > 0 else { return nil }
            return CapturedPCM.Buffer(data: Data(bytes: bytes, count: Int(buffer.mDataByteSize)),
                                      channelCount: Int(buffer.mNumberChannels))
        }
        guard !buffers.isEmpty else { return }
        let capture = CapturedPCM(buffers: buffers)
        queue.async { [weak self] in self?.consume(capture) }
    }

    func reset() {
        queue.async { [weak self] in
            guard let self else { return }
            pending = Array(repeating: [], count: Int(format.mChannelsPerFrame))
            lastEmission = 0
        }
    }

    private func consume(_ capture: CapturedPCM) {
        guard let channels = decode(capture), channels.count == pending.count else { return }
        for index in channels.indices { pending[index].append(contentsOf: channels[index]) }
        let count = AudioSpectrumAnalyzer.sampleCount
        guard pending.allSatisfy({ $0.count >= count }) else { return }
        pending = pending.map { Array($0.suffix(count)) }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastEmission >= 1.0 / 30 else { return }
        lastEmission = now
        publish(spectrum.levels(channels: pending, sampleRate: format.mSampleRate))
    }

    private func decode(_ capture: CapturedPCM) -> [[Float]]? {
        let flags = format.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = flags & kAudioFormatFlagIsSignedInteger != 0
        let isBigEndian = flags & kAudioFormatFlagIsBigEndian != 0
        let bytesPerSample = Int(format.mBitsPerChannel / 8)
        guard format.mFormatID == kAudioFormatLinearPCM,
              (isFloat || isSignedInteger), !isBigEndian,
              [2, 3, 4, 8].contains(bytesPerSample) else {
            logUnsupportedFormatOnce()
            return nil
        }

        var result = Array(repeating: [Float](), count: Int(format.mChannelsPerFrame))
        var channelOffset = 0
        for buffer in capture.buffers {
            guard buffer.channelCount > 0, channelOffset + buffer.channelCount <= result.count else { return nil }
            let frameCount = buffer.data.count / (bytesPerSample * buffer.channelCount)
            buffer.data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                for frame in 0..<frameCount {
                    for channel in 0..<buffer.channelCount {
                        let offset = (frame * buffer.channelCount + channel) * bytesPerSample
                        result[channelOffset + channel].append(sample(at: base.advanced(by: offset),
                                                                      bytes: bytesPerSample,
                                                                      isFloat: isFloat))
                    }
                }
            }
            channelOffset += buffer.channelCount
        }
        return channelOffset == result.count ? result : nil
    }

    private func sample(at pointer: UnsafeRawPointer, bytes: Int, isFloat: Bool) -> Float {
        if isFloat {
            if bytes == 4 { return pointer.loadUnaligned(as: Float.self).isFinite ? pointer.loadUnaligned(as: Float.self) : 0 }
            if bytes == 8 {
                let value = pointer.loadUnaligned(as: Double.self)
                return value.isFinite ? Float(value) : 0
            }
            return 0
        }
        switch bytes {
        case 2: return Float(pointer.loadUnaligned(as: Int16.self)) / Float(Int16.max)
        case 3:
            let bytes = pointer.assumingMemoryBound(to: UInt8.self)
            var value = Int32(bytes[0]) | (Int32(bytes[1]) << 8) | (Int32(bytes[2]) << 16)
            if value & 0x0080_0000 != 0 { value |= ~0x00FF_FFFF }
            return Float(value) / 8_388_607
        case 4: return Float(pointer.loadUnaligned(as: Int32.self)) / Float(Int32.max)
        default: return 0
        }
    }

    private func logUnsupportedFormatOnce() {
        guard !didLogUnsupportedFormat else { return }
        didLogUnsupportedFormat = true
        NSLog("[SpotifyAudioTap] Unsupported PCM format: flags=%u bits=%u", format.mFormatFlags, format.mBitsPerChannel)
    }
}
