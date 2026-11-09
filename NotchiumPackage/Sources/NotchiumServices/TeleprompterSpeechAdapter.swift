import AVFoundation
import CoreMedia
import Foundation
import Speech

/// macOS 26's on-device recognizer. This adapter has a single capture owner and uses
/// generation checks at each suspension so cancelled preparation cannot reopen the mic.
public actor RealTeleprompterSpeechService: TeleprompterSpeechService {
    private var generation = 0
    private var events: AsyncStream<TeleprompterSpeechEvent>.Continuation?
    private var microphoneInput: AsyncStream<TeleprompterMicrophonePacket>.Continuation?
    private var analyzerInput: AsyncStream<AnalyzerInput>.Continuation?
    private var preparationTask: Task<Void, Never>?
    private var conversionTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var installationRequest: AssetInstallationRequest?
    private var configurationObserver: NSObjectProtocol?
    private var lifecycleObserver: TeleprompterSpeechLifecycleObserver?
    private var tapInstalled = false

    public init() {}

    public func inputDevices() async -> [TeleprompterMicrophone] {
        TeleprompterMicrophoneHardware.devices().map(\.microphone)
    }

    private static func transcriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [.audioTimeRange])
    }

    isolated deinit {
        preparationTask?.cancel()
        conversionTask?.cancel()
        resultTask?.cancel()
        analysisTask?.cancel()
        installationRequest?.progress.cancel()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        engine?.stop()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        microphoneInput?.finish()
        analyzerInput?.finish()
        events?.finish()
    }

    public func availability(localeIdentifier: String) async -> TeleprompterSpeechAvailability {
        guard SpeechTranscriber.isAvailable else { return .unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier)) else {
            return .unsupportedLocale
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .microphoneNotDetermined
        case .authorized: break
        @unknown default: return .unavailable
        }
        let transcriber = Self.transcriber(locale: locale)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: return .available
        case .supported, .downloading: return .requiresDownload
        case .unsupported: return .unsupportedLocale
        @unknown default: return .unavailable
        }
    }

    public func start(localeIdentifier: String) async throws -> AsyncStream<TeleprompterSpeechEvent> {
        try await start(localeIdentifier: localeIdentifier, inputDeviceID: nil)
    }

    public func start(localeIdentifier: String, inputDeviceID: String?) async throws -> AsyncStream<TeleprompterSpeechEvent> {
        let old = reset()
        let token = generation
        await old.lifecycle?.stop()
        if let analyzer = old.analyzer { await analyzer.cancelAndFinishNow() }
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        let pair = AsyncStream.makeStream(of: TeleprompterSpeechEvent.self, bufferingPolicy: .bufferingNewest(64))
        events = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.stop(ifCurrent: token) }
        }
        pair.continuation.yield(.preparing)
        preparationTask = Task { [weak self] in
            await self?.prepare(localeIdentifier: localeIdentifier, inputDeviceID: inputDeviceID, token: token)
        }
        return pair.stream
    }

    public func stop() async {
        let old = reset()
        await old.lifecycle?.stop()
        if let analyzer = old.analyzer { await analyzer.cancelAndFinishNow() }
    }

    private func prepare(localeIdentifier: String, inputDeviceID: String?, token: Int) async {
        do {
            let lifecycle = await TeleprompterSpeechLifecycleObserver { [weak self] event in
                Task { await self?.handleLifecycle(event, token: token) }
            }
            guard generation == token, !Task.isCancelled else {
                await lifecycle.stop()
                throw CancellationError()
            }
            lifecycleObserver = lifecycle
            guard SpeechTranscriber.isAvailable else { throw TeleprompterSpeechFailure.unavailable }
            let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier))
            try checkCurrent(token)
            guard let locale = supportedLocale else { throw TeleprompterSpeechFailure.unsupportedLocale }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined:
                let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                try checkCurrent(token)
                guard allowed else { throw TeleprompterSpeechFailure.microphoneDenied }
            case .denied: throw TeleprompterSpeechFailure.microphoneDenied
            case .restricted: throw TeleprompterSpeechFailure.microphoneRestricted
            case .authorized: break
            @unknown default: throw TeleprompterSpeechFailure.microphoneDenied
            }
            let transcriber = Self.transcriber(locale: locale)
            let request: AssetInstallationRequest?
            do { request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) }
            catch {
                try checkCurrent(token)
                throw TeleprompterSpeechFailure.assetsUnavailable
            }
            try checkCurrent(token)
            if let request {
                events?.yield(.downloadingAssets)
                installationRequest = request
                do { try await request.downloadAndInstall() }
                catch {
                    try checkCurrent(token)
                    throw TeleprompterSpeechFailure.assetsUnavailable
                }
                try checkCurrent(token)
                installationRequest = nil
            }
            try await beginCapture(transcriber: transcriber, inputDeviceID: inputDeviceID, token: token)
        } catch is CancellationError {
            // stop/replacement owns cleanup; cancellation is never shown as a failure.
        } catch let error as TeleprompterSpeechFailure {
            await fail(error, token: token)
        } catch {
            await fail(.recognitionFailed, token: token)
        }
    }

    private func beginCapture(transcriber: SpeechTranscriber, inputDeviceID: String?, token: Int) async throws {
        try checkCurrent(token)
        let capture = AVAudioEngine()
        let source = capture.inputNode
        if let inputDeviceID {
            guard let device = TeleprompterMicrophoneHardware.devices().first(where: { $0.microphone.id == inputDeviceID }) else {
                throw TeleprompterSpeechFailure.audioInputUnavailable
            }
            do { try source.auAudioUnit.setDeviceID(device.objectID) }
            catch { throw TeleprompterSpeechFailure.audioInputUnavailable }
        }
        let naturalFormat = source.outputFormat(forBus: 0)
        guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0,
              naturalFormat.channelCount <= 8, naturalFormat.commonFormat == .pcmFormatFloat32 else {
            throw TeleprompterSpeechFailure.audioInputUnavailable
        }
        let supported = await transcriber.availableCompatibleAudioFormats
        try checkCurrent(token)
        let preferred = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                      channels: 1, interleaved: false)
        let negotiated = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: preferred)
        try checkCurrent(token)
        guard let format = TeleprompterSpeechAudioConverter.selectAnalyzerFormat(supported: supported, negotiated: negotiated),
              let converter = TeleprompterSpeechAudioConverter(inputFormat: naturalFormat, outputFormat: format) else {
            throw TeleprompterSpeechFailure.audioInputUnavailable
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        engine = capture
        try await analyzer.prepareToAnalyze(in: format)
        try checkCurrent(token)

        let capacity = TeleprompterAudioBuffering.packetCapacity(sampleRate: naturalFormat.sampleRate)
        let microphone = AsyncStream.makeStream(of: TeleprompterMicrophonePacket.self, bufferingPolicy: .bufferingOldest(capacity))
        let input = AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .bufferingOldest(capacity))
        microphoneInput = microphone.continuation
        analyzerInput = input.continuation

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: capture, queue: nil
        ) { [weak self] _ in
            Task { await self?.fail(.audioConfigurationChanged, token: token) }
        }

        startTasks(transcriber: transcriber, analyzer: analyzer, converter: converter,
                   microphone: microphone.stream, input: input.stream,
                   inputBuilder: input.continuation, token: token)

        let levelGate = TeleprompterAudioLevelGate(sampleRate: naturalFormat.sampleRate)
        let output = events
        source.installTap(onBus: 0, bufferSize: 1024, format: naturalFormat) { buffer, time in
            guard let packet = TeleprompterMicrophonePacket.copying(buffer, at: time) else { return }
            if levelGate.shouldReport(frameCount: packet.frameCount) {
                output?.yield(.audioLevel(packet.rms))
            }
            if case .dropped = microphone.continuation.yield(packet) {
                // A prolonged backlog must be visible as processing overload, not
                // misreported as a missing microphone or silent transcription.
                output?.yield(.failure(.audioProcessingOverloaded))
                microphone.continuation.finish()
            }
        }
        tapInstalled = true
        capture.prepare()
        do { try capture.start() }
        catch { throw TeleprompterSpeechFailure.audioInputUnavailable }
        try checkCurrent(token)
        events?.yield(.inputDevice(name: TeleprompterMicrophoneHardware.name(for: source.auAudioUnit.deviceID) ?? "Microphone"))
        events?.yield(.ready)
    }

    private func startTasks(transcriber: SpeechTranscriber, analyzer: SpeechAnalyzer,
                            converter: TeleprompterSpeechAudioConverter,
                            microphone: AsyncStream<TeleprompterMicrophonePacket>,
                            input: AsyncStream<AnalyzerInput>, inputBuilder: AsyncStream<AnalyzerInput>.Continuation,
                            token: Int) {
        conversionTask = Task { [weak self] in
            do {
                for await packet in microphone {
                    try Task.checkCancellation()
                    guard let self else { return }
                    try await self.checkCurrent(token)
                    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                        throw TeleprompterSpeechFailure.microphoneDenied
                    }
                    if let converted = try await converter.convert(packet) {
                        if case .dropped = inputBuilder.yield(converted) {
                            throw TeleprompterSpeechFailure.audioProcessingOverloaded
                        }
                    }
                }
                if !Task.isCancelled { await self?.fail(.audioInputUnavailable, token: token) }
            } catch is CancellationError {
                // The session owner already ended capture.
            } catch let error as TeleprompterSpeechFailure {
                await self?.fail(error, token: token)
            } catch {
                await self?.fail(.recognitionFailed, token: token)
            }
            inputBuilder.finish()
        }
        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    let start = CMTimeGetSeconds(result.range.start)
                    let end = CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
                    guard start.isFinite, end.isFinite, end >= start else { continue }
                    await self?.receive(.transcript(text: String(result.text.characters), audioStart: start,
                                                   audioEnd: end, isFinal: result.isFinal), token: token)
                }
                if !Task.isCancelled { await self?.fail(.recognitionFailed, token: token) }
            } catch {
                if !Task.isCancelled { await self?.fail(.recognitionFailed, token: token) }
            }
        }
        analysisTask = Task { [weak self] in
            do {
                _ = try await analyzer.analyzeSequence(input)
                try Task.checkCancellation()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                await self?.fail(.recognitionFailed, token: token)
            } catch {
                if !Task.isCancelled { await self?.fail(.recognitionFailed, token: token) }
            }
        }
    }

    private func checkCurrent(_ token: Int) throws {
        try Task.checkCancellation()
        guard generation == token, events != nil else { throw CancellationError() }
    }

    private func receive(_ event: TeleprompterSpeechEvent, token: Int) {
        guard generation == token else { return }
        events?.yield(event)
    }

    private func fail(_ failure: TeleprompterSpeechFailure, token: Int) async {
        guard generation == token, events != nil else { return }
        events?.yield(.failure(failure))
        await stop()
    }

    private func handleLifecycle(_ event: TeleprompterSpeechLifecycleEvent, token: Int) async {
        guard generation == token, events != nil else { return }
        switch event {
        case .suspend:
            await fail(.sessionInterrupted, token: token)
        case .becameActive:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized, .notDetermined: break
            case .denied: await fail(.microphoneDenied, token: token)
            case .restricted: await fail(.microphoneRestricted, token: token)
            @unknown default: await fail(.microphoneDenied, token: token)
            }
        }
    }

    private func stop(ifCurrent token: Int) async {
        guard generation == token else { return }
        await stop()
    }

    /// Synchronous teardown happens before awaiting SpeechAnalyzer, preventing another
    /// start from inheriting an older engine or continuation during actor reentrancy.
    private func reset() -> (analyzer: SpeechAnalyzer?, lifecycle: TeleprompterSpeechLifecycleObserver?) {
        generation &+= 1
        preparationTask?.cancel(); preparationTask = nil
        conversionTask?.cancel(); conversionTask = nil
        resultTask?.cancel(); resultTask = nil
        analysisTask?.cancel(); analysisTask = nil
        installationRequest?.progress.cancel(); installationRequest = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        engine?.stop(); engine = nil
        microphoneInput?.finish(); microphoneInput = nil
        analyzerInput?.finish(); analyzerInput = nil
        events?.finish(); events = nil
        let previous = analyzer
        analyzer = nil
        let lifecycle = lifecycleObserver
        lifecycleObserver = nil
        return (previous, lifecycle)
    }
}
