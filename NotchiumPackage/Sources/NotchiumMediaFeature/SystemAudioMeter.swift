import Foundation
import Combine
import CoreGraphics

/// Owned by the app's media session, never by a view or a Space.
@MainActor
public final class SystemAudioMeter: ObservableObject {
    public enum Status: Equatable { case idle, starting, capturing, permissionRequired, unavailable }
    public static let staticLevels = [CGFloat](repeating: 0.12, count: 7)
    @Published public private(set) var waveformLevels = staticLevels
    @Published public private(set) var status: Status = .idle
    private let capture: any SystemAudioCapturing
    private let captureEnabled: Bool
    private let permissionGranted: @MainActor () -> Bool
    private var wantsCapture = false
    private var monitorsPlaybackActivity = false
    private var isPlaying = false
    private var captureStarted = false
    private var captureFailed = false
    private var lifecycleTask: Task<Void, Never>?
    private var playbackActivityHandler: (@MainActor @Sendable () -> Void)?
    public var isRunning: Bool { status == .capturing }
    private var generation = 0
    #if DEBUG
    private var lastDebugLevels = Date.distantPast
    #endif

    public convenience init(captureEnabled: Bool = true) {
        self.init(capture: SpotifyAudioTap(), captureEnabled: captureEnabled,
                  permissionGranted: { true })
    }
    init(capture: any SystemAudioCapturing, captureEnabled: Bool = true,
         permissionGranted: @escaping @MainActor () -> Bool) {
        self.capture = capture; self.captureEnabled = captureEnabled
        self.permissionGranted = permissionGranted
    }

    public func setPlaying(_ playing: Bool) {
        #if DEBUG
        if playing != isPlaying {
            print("[Waveform] media isPlaying=\(playing)")
            print("[Waveform] meter running=\(isRunning) status=\(status)")
        }
        #endif
        if playing && !isPlaying { captureFailed = false }
        isPlaying = playing
        if !playing { waveformLevels = Self.staticLevels }
        updateCaptureIntent()
    }

    /// Keeps the Spotify-only tap available as a wake-up signal while playback metadata is
    /// inactive or paused. Audio remains a signal only; Spotify is still the metadata source.
    public func setMonitoringPlaybackActivity(_ monitoring: Bool) {
        monitorsPlaybackActivity = monitoring
        updateCaptureIntent()
    }

    public func setPlaybackActivityHandler(_ handler: (@MainActor @Sendable () -> Void)?) {
        playbackActivityHandler = handler
    }

    public func stop() {
        monitorsPlaybackActivity = false
        wantsCapture = false; isPlaying = false
        waveformLevels = Self.staticLevels
        reconcile()
    }

    /// Explicit retry action. Core Audio owns the system-audio permission prompt and
    /// doesn't expose a separate preflight/request API.
    public func requestPermission() {
        guard captureEnabled else { return }
        captureFailed = false
        if isPlaying || monitorsPlaybackActivity {
            wantsCapture = true
            reconcile()
        } else {
            status = .idle
        }
    }

    private func updateCaptureIntent() {
        let shouldCapture = isPlaying || monitorsPlaybackActivity
        guard !shouldCapture || !captureFailed else { return }
        guard shouldCapture != wantsCapture else { return }
        wantsCapture = shouldCapture
        reconcile()
    }

    private func reconcile() {
        guard lifecycleTask == nil else { return }
        // Serialize start/stop, including a resume while stopCapture is suspended.
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            defer { self.lifecycleTask = nil }
            while true {
                if !self.wantsCapture {
                    self.generation &+= 1
                    if self.captureStarted {
                        await self.capture.stop()
                        self.captureStarted = false
                        continue
                    }
                    if self.status == .capturing || self.status == .starting { self.status = .idle }
                    return
                }
                guard !self.captureStarted else { return }
                guard self.captureEnabled else { self.status = .unavailable; return }
                guard self.permissionGranted() else { self.status = .permissionRequired; return }
                self.status = .starting
                self.generation &+= 1
                let generation = self.generation
                self.captureStarted = true
                do {
                    try await self.capture.start { [weak self] levels in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == generation,
                                  self.wantsCapture, !self.captureFailed,
                                  levels.count == 7 else { return }
                            if !self.isPlaying,
                               levels.contains(where: { $0 > AudioSpectrumAnalyzer.minimum + 0.02 }) {
                                self.playbackActivityHandler?()
                            }
                            guard self.isPlaying else { return }
                            self.waveformLevels = levels.map { $0.isFinite ? min(1, max(0.12, $0)) : 0.12 }
                            #if DEBUG
                            if Date().timeIntervalSince(self.lastDebugLevels) >= 5 {
                                self.lastDebugLevels = Date()
                                NSLog("[Waveform] Updating levels")
                            }
                            #endif
                        }
                    } failure: { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == generation else { return }
                            self.captureFailed = true; self.wantsCapture = false
                            self.status = .unavailable; self.waveformLevels = Self.staticLevels
                            self.reconcile()
                        }
                    }
                    if !self.captureFailed { self.status = .capturing }
                } catch {
                    self.wantsCapture = false
                    self.generation &+= 1
                    await self.capture.stop()
                    self.captureStarted = false
                    self.captureFailed = true
                    self.status = error as? SystemAudioCaptureError == .permissionDenied
                        ? .permissionRequired : .unavailable
                    self.waveformLevels = Self.staticLevels
                    return
                }
            }
        }
    }
}
