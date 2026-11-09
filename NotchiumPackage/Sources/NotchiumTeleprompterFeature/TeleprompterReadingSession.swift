import Foundation
import NotchiumCore
import NotchiumServices
import Observation

public enum TeleprompterReadingState: Equatable, Sendable {
    case idle, preparing, downloading, reading, waiting, paused, finished, failed
}

/// One immutable script and one microphone owner, shared by every display projection.
@MainActor @Observable
public final class TeleprompterReadingSession {
    public private(set) var state: TeleprompterReadingState = .idle
    public private(set) var alignment = TeleprompterAlignment(text: "")
    public private(set) var position: Double = 0
    public private(set) var message: String?
    public private(set) var inputLevel: Double = 0
    public private(set) var inputDeviceName: String?
    public private(set) var availableMicrophones: [TeleprompterMicrophone] = []
    public private(set) var hasRecognizedSpeech = false
    public var inputDeviceID: String? {
        didSet { if oldValue != inputDeviceID { pause(); inputDeviceName = nil } }
    }
    public var microphoneDescription: String {
        inputDeviceName ?? availableMicrophones.first(where: { $0.id == inputDeviceID })?.name
            ?? availableMicrophones.first(where: \.isDefault)?.name ?? "System default"
    }
    public var mode: TeleprompterMode = .voiceFollow {
        didSet { if oldValue != mode { pause() } }
    }
    public var wordsPerMinute: Double = 140 {
        didSet {
            // Observation's generated setter re-enters this observer on assignment.
            let bounded = wordsPerMinute.isFinite ? min(300, max(50, wordsPerMinute)) : 140
            if wordsPerMinute != bounded { wordsPerMinute = bounded }
        }
    }
    public var localeIdentifier = "en-US" {
        didSet { if oldValue != localeIdentifier { pause() } }
    }
    public var fontSize: Double = TeleprompterReaderStyle.defaultFontSize {
        didSet {
            let range = TeleprompterReaderStyle.fontRange
            let bounded = fontSize.isFinite ? min(range.upperBound, max(range.lowerBound, fontSize))
                : TeleprompterReaderStyle.defaultFontSize
            if fontSize != bounded { fontSize = bounded }
        }
    }
    public var isActive: Bool { [.preparing, .downloading, .reading, .waiting].contains(state) }
    public var wordIndex: Int { min(alignment.wordCount, max(0, Int(position))) }
    public var fraction: Double { alignment.wordCount == 0 ? 0 : position / Double(alignment.wordCount) }
    public var statusText: String {
        switch state {
        case .idle: "Ready"
        case .preparing: "Preparing microphone…"
        case .downloading: "Downloading local speech model…"
        case .reading: mode == .fixedSpeed ? "Fixed pace · microphone off" : "Following · microphone on"
        case .waiting:
            hasRecognizedSpeech ? "Speech heard · finding your place" : "Listening · \(inputDeviceName ?? "microphone on")"
        case .paused: "Paused · microphone off"
        case .finished: "Finished · microphone off"
        case .failed: "Reading stopped"
        }
    }

    @ObservationIgnored private let speech: any TeleprompterSpeechService
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var speechTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var deviceListTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var lastMatch: Date?
    @ObservationIgnored private var lastVoice: Date?
    @ObservationIgnored private var confirmedWord = 0
    @ObservationIgnored private var openingWord = 0
    @ObservationIgnored private var transcriptParts: [TranscriptPart] = []
    @ObservationIgnored private var lastEvidence = ""
    @ObservationIgnored private var lastEvidenceIsFinal = true
    @ObservationIgnored private var lastMatchedAudioEnd = -TimeInterval.infinity
    @ObservationIgnored private var discardThroughAudioEnd = -TimeInterval.infinity

    private struct TranscriptPart {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
        let isFinal: Bool
    }

    public init(speech: any TeleprompterSpeechService, clock: any AppClock) {
        self.speech = speech
        self.clock = clock
    }

    public func refreshInputDevices() {
        deviceListTask?.cancel()
        deviceListTask = Task { [weak self, speech] in
            let devices = await speech.inputDevices()
            guard !Task.isCancelled, let self else { return }
            self.availableMicrophones = devices
            self.deviceListTask = nil
        }
    }

    public func prepare(text: String) {
        stop()
        alignment = TeleprompterAlignment(text: text)
        position = 0
        confirmedWord = 0
    }

    public func start() {
        guard !isActive, alignment.wordCount > 0 else { return }
        if wordIndex >= alignment.wordCount { seek(to: 0) }
        generation &+= 1
        let token = generation
        message = nil
        inputLevel = 0
        inputDeviceName = nil
        hasRecognizedSpeech = false
        lastTick = nil
        lastMatch = nil
        lastVoice = nil
        transcriptParts.removeAll()
        lastEvidence = ""
        lastEvidenceIsFinal = true
        lastMatchedAudioEnd = -.infinity
        discardThroughAudioEnd = -.infinity
        confirmedWord = wordIndex
        openingWord = wordIndex
        let previousStop = stopTask
        let locale = localeIdentifier
        let selectedInput = inputDeviceID
        if mode == .fixedSpeed {
            state = .reading
            startTicker(token: token)
            return
        }
        state = .preparing
        speechTask = Task { [weak self, speech, clock] in
            await previousStop?.value
            guard !Task.isCancelled else { return }
            do {
                let events = try await speech.start(localeIdentifier: locale, inputDeviceID: selectedInput)
                for await event in events {
                    let date = await clock.now()
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    self.receive(event, at: date, token: token)
                }
                guard !Task.isCancelled, let self, self.generation == token, self.isActive else { return }
                self.fail(.recognitionFailed)
            } catch is CancellationError {
                // Explicit pause, closing the reader, and sleep cancel an owned session.
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.fail((error as? TeleprompterSpeechFailure) ?? .recognitionFailed)
            }
        }
    }

    public func pause() {
        guard isActive else { return }
        endCapture()
        state = .paused
    }

    public func stop() {
        endCapture()
        state = .idle
        message = nil
    }

    public func restart() {
        pause()
        seek(to: 0)
    }

    public func seek(to index: Int) {
        position = Double(min(alignment.wordCount, max(0, index)))
        confirmedWord = wordIndex
        openingWord = wordIndex
        // A delayed revision of speech heard before a deliberate seek must not
        // reactivate the new position, especially when paragraphs repeat.
        discardThroughAudioEnd = max(discardThroughAudioEnd, transcriptParts.map(\.end).max() ?? -.infinity)
        transcriptParts.removeAll()
        lastEvidence = ""
        lastEvidenceIsFinal = true
        lastMatch = nil
        lastVoice = nil
        if (state == .reading || state == .waiting), mode.usesMicrophone { state = .waiting }
        if state == .finished { state = .paused }
    }

    public func moveParagraph(forward: Bool) {
        let paragraphs = alignment.paragraphs
        let current = paragraphs.lastIndex(where: { $0.wordRange.lowerBound <= wordIndex }) ?? 0
        let next = min(paragraphs.count - 1, max(0, current + (forward ? 1 : -1)))
        guard paragraphs.indices.contains(next) else { return }
        seek(to: paragraphs[next].wordRange.lowerBound)
    }

    private func startTicker(token: Int) {
        tickTask?.cancel()
        tickTask = Task { [weak self, clock] in
            let initialDate = await clock.now()
            guard !Task.isCancelled, self?.generation == token else { return }
            self?.lastTick = initialDate
            while !Task.isCancelled {
                do { try await clock.sleep(for: .milliseconds(100)) } catch { return }
                let date = await clock.now()
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.advance(at: date)
            }
        }
    }

    /// Injected time makes scrolling, silence, and off-script holding deterministic.
    func advance(at date: Date) {
        guard state == .reading || state == .waiting else { return }
        let elapsed = min(0.25, max(0, date.timeIntervalSince(lastTick ?? date)))
        lastTick = date
        if mode != .fixedSpeed {
            let matched = lastMatch.map { date.timeIntervalSince($0) < 1.5 } ?? false
            let voiced = lastVoice.map { date.timeIntervalSince($0) < 0.65 } ?? false
            let justMatched = lastMatch.map { date.timeIntervalSince($0) < 0.25 } ?? false
            state = matched && (voiced || justMatched) ? .reading : .waiting
        }
        if state == .reading, mode != .voiceFollow {
            let limit = mode == .voiceGated ? min(alignment.wordCount, confirmedWord + 3) : alignment.wordCount
            position = min(Double(limit), position + wordsPerMinute / 60 * elapsed)
        }
        finishIfNeeded()
    }

    private func receive(_ event: TeleprompterSpeechEvent, at date: Date, token: Int) {
        switch event {
        case .preparing: state = .preparing
        case .downloadingAssets: state = .downloading
        case .ready:
            state = .waiting
            startTicker(token: token)
        case let .inputDevice(name): inputDeviceName = name
        case let .audioLevel(level):
            let rms = level.isFinite ? min(1, max(0, level)) : 0
            // A logarithmic meter makes quiet input visible. Energy is only a
            // continuation hint; advancing still requires lexical script matches.
            inputLevel = rms > 0 ? min(1, max(0, (20 * log10(rms) + 70) / 50)) : 0
            if rms > 0.0005 { lastVoice = date }
        case let .transcript(text, start, end, isFinal):
            receiveTranscript(text, start: start, end: end, isFinal: isFinal, at: date)
        case let .failure(error): fail(error)
        }
    }

    private func receiveTranscript(_ text: String, start: TimeInterval, end: TimeInterval, isFinal: Bool, at date: Date) {
        guard start.isFinite, end.isFinite, end >= start, end > discardThroughAudioEnd else { return }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hasRecognizedSpeech = true }
        // Volatile recognition replaces overlapping audio ranges, including revisions of finals.
        transcriptParts.removeAll { $0.start < end && start < $0.end || abs($0.start - start) < 0.001 }
        transcriptParts.append(.init(start: start, end: end, text: text, isFinal: isFinal))
        transcriptParts.sort { $0.start < $1.start }
        transcriptParts.removeAll { $0.end < end - 8 }
        transcriptParts = Array(transcriptParts.suffix(16))
        let evidence = transcriptParts.map(\.text).joined(separator: " ")
        // A late final may revise an earlier range while the latest range still
        // ends in an unfinished word. Finality belongs to that latest text part.
        let evidenceIsFinal = transcriptParts.last?.isFinal ?? isFinal
        guard evidence != lastEvidence || evidenceIsFinal != lastEvidenceIsFinal else { return }
        lastEvidence = evidence
        lastEvidenceIsFinal = evidenceIsFinal
        // A nonfinal trailing prefix is not an off-script detour. Match only its
        // completed context, and retain the previous bounded grace without renewal.
        // Check this before fuzzy full matching, which could mistake “quarterl” for
        // the completed “quarterly” and prematurely mark the unfinished word read.
        let provisional = evidenceIsFinal ? nil : TeleprompterPartialMatch.completedPrefix(in: evidence,
            alignment: alignment, near: wordIndex, confirmedWord: confirmedWord)
        let opening = confirmedWord < openingWord + 3
            ? alignment.matchOpening(transcript: evidence, at: openingWord, allowTrailingPartial: !evidenceIsFinal) : nil
        guard let match = provisional ?? opening ?? alignment.match(transcript: evidence, near: wordIndex) else {
            lastMatch = nil
            state = .waiting
            return
        }
        // An overlapping revision must advance the confirmed words. Fresh audio
        // can repeat a phrase after a seek; a late final of consumed audio cannot
        // reopen the gate just because punctuation or number formatting changed.
        guard match.nextWordIndex > confirmedWord || (provisional == nil && start >= lastMatchedAudioEnd) else { return }
        lastMatchedAudioEnd = max(lastMatchedAudioEnd, end)
        lastMatch = date
        lastVoice = date
        state = .reading
        confirmedWord = max(confirmedWord, match.nextWordIndex)
        if mode == .voiceFollow { position = max(position, Double(match.nextWordIndex)) }
        else if mode == .voiceGated, match.matchedWordRange.lowerBound > wordIndex + 8 {
            // A strong reacquisition may skip a heading/sentence; fixed pace must
            // start at that phrase instead of scrolling from a stale old paragraph.
            position = Double(match.matchedWordRange.lowerBound)
        }
        finishIfNeeded()
    }

    private func finishIfNeeded() {
        guard alignment.wordCount > 0, wordIndex >= alignment.wordCount else { return }
        endCapture()
        state = .finished
    }

    private func fail(_ failure: TeleprompterSpeechFailure) {
        endCapture()
        state = .failed
        switch failure {
        case .microphoneDenied: message = "Allow Microphone access in System Settings → Privacy & Security, or choose Fixed Speed."
        case .microphoneRestricted: message = "Microphone access is restricted on this Mac. Fixed Speed still works."
        case .unsupportedLocale: message = "On-device speech is unavailable for this language. Choose another language or Fixed Speed."
        case .unavailable: message = "On-device speech is unavailable on this Mac. Fixed Speed still works."
        case .assetsUnavailable: message = "The local speech model couldn’t be downloaded. Check your connection and try again."
        case .audioInputUnavailable:
            message = inputDeviceID == nil
                ? "No microphone input is available. Check your input device or choose Fixed Speed."
                : "The selected microphone is unavailable. Choose another input and try again."
        case .audioConfigurationChanged: message = "The microphone changed. Check your input device, then press Resume."
        case .sessionInterrupted:
            state = .paused
            message = "Reading paused while your Mac was inactive. Press Resume when you’re ready."
        case .recognitionFailed: message = "Speech following stopped. Your position is saved; try again or choose Fixed Speed."
        case .audioProcessingOverloaded: message = "Audio processing fell behind. Your position is saved; close busy apps and press Resume."
        }
    }

    private func endCapture() {
        inputLevel = 0
        generation &+= 1
        speechTask?.cancel(); speechTask = nil
        tickTask?.cancel(); tickTask = nil
        let previous = stopTask
        stopTask = Task { [speech] in
            await previous?.value
            await speech.stop()
        }
    }

    isolated deinit {
        speechTask?.cancel()
        tickTask?.cancel()
        deviceListTask?.cancel()
    }
}
