import Foundation
import AppKit
import Observation
import CoreGraphics
import NotchiumCore

/// Owned by the app's media session, never by a view or a Space.
@MainActor
@Observable
public final class SystemAudioMeter {
    public enum Status: Equatable { case idle, starting, capturing, permissionRequired, unavailable }
    public static let staticLevels = [CGFloat](repeating: 0.12, count: 7)
    private static let activityThreshold = AudioSpectrumAnalyzer.minimum + 0.02
    // Keep artwork and waveform visible through short silent gaps between Spotify tracks.
    // Explicit pause, device changes, and capture failures still clear activity immediately.
    static let activityTimeout: Duration = .milliseconds(1_500)
    public private(set) var waveformLevels = staticLevels
    public private(set) var status: Status = .idle
    public private(set) var isAudioActive = false
    private let capture: any SystemAudioCapturing
    private let captureEnabled: Bool
    private let permissionGranted: @MainActor () -> Bool
    private let activityClock: any AppClock
    @ObservationIgnored private var activationObservers: [(NotificationCenter, any NSObjectProtocol)] = []
    @ObservationIgnored private var wantsCapture = false
    @ObservationIgnored private var monitorsPlaybackActivity = false
    @ObservationIgnored private var isPlaying = false
    @ObservationIgnored private var waveformPresentationEnabled = true
    @ObservationIgnored private var captureStarted = false
    @ObservationIgnored private var captureFailed = false
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var activationRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var inactivityTask: Task<Void, Never>?
    @ObservationIgnored private var playbackActivityHandler: (@MainActor @Sendable () -> Void)?
    @ObservationIgnored private var localAudioActivityHandler: (@MainActor @Sendable (Bool) -> Void)?
    public var isRunning: Bool { status == .capturing }
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activityGeneration = 0

    public convenience init(
        captureEnabled: Bool = true,
        activityClock: any AppClock = ContinuousAppClock()
    ) {
        self.init(capture: SpotifyAudioTap(), captureEnabled: captureEnabled,
                  permissionGranted: { true }, activityClock: activityClock,
                  notificationCenter: .default,
                  workspaceNotificationCenter: NSWorkspace.shared.notificationCenter)
    }
    init(capture: any SystemAudioCapturing, captureEnabled: Bool = true,
         permissionGranted: @escaping @MainActor () -> Bool,
         activityClock: any AppClock = ContinuousAppClock(),
         notificationCenter: NotificationCenter? = nil,
         workspaceNotificationCenter: NotificationCenter? = nil) {
        self.capture = capture; self.captureEnabled = captureEnabled
        self.permissionGranted = permissionGranted
        self.activityClock = activityClock
        if captureEnabled {
            // A menu-bar app may stay inactive when the user returns from Settings to Spotify.
            for (center, name) in [(notificationCenter, NSApplication.didBecomeActiveNotification),
                                   (workspaceNotificationCenter, NSWorkspace.didActivateApplicationNotification)] {
                guard let center else { continue }
                let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    // The observer's explicit main queue matches this meter's isolation.
                    MainActor.assumeIsolated { self?.recoverAfterActivation() }
                }
                activationObservers.append((center, token))
            }
        }
    }

    isolated deinit {
        for (center, token) in activationObservers { center.removeObserver(token) }
        activationRecoveryTask?.cancel()
    }

    public func setPlaying(_ playing: Bool) {
        if playing && !isPlaying { captureFailed = false }
        let didStopPlaying = !playing && isPlaying
        isPlaying = playing
        if didStopPlaying {
            setAudioActive(false)
        }
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

    func setLocalAudioActivityHandler(
        _ handler: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        localAudioActivityHandler = handler
    }

    func setWaveformPresentationEnabled(_ enabled: Bool) {
        waveformPresentationEnabled = enabled
    }

    /// A new Spotify Connect target invalidates samples attributed to the previous target.
    func resetLocalAudioActivity() {
        setAudioActive(false)
    }

    public func stop() {
        activationRecoveryTask?.cancel()
        activationRecoveryTask = nil
        monitorsPlaybackActivity = false
        wantsCapture = false; isPlaying = false
        waveformLevels = Self.staticLevels
        setAudioActive(false)
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

    /// macOS may grant access while playback remains unchanged. Returning from its
    /// dialog or Settings is a recovery event; ordinary metadata polling is not.
    private func recoverAfterActivation() {
        guard isPlaying || monitorsPlaybackActivity, activationRecoveryTask == nil else { return }
        let pendingLifecycle = lifecycleTask
        activationRecoveryTask = Task { [weak self] in
            // Activation can arrive before the original consent attempt finishes.
            await pendingLifecycle?.value
            guard !Task.isCancelled, let self else { return }
            defer { self.activationRecoveryTask = nil }
            guard self.isPlaying || self.monitorsPlaybackActivity,
                  self.status == .permissionRequired || self.status == .unavailable else { return }
            self.requestPermission()
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
                            let normalized = levels.map {
                                $0.isFinite ? min(1, max(AudioSpectrumAnalyzer.minimum, $0))
                                    : AudioSpectrumAnalyzer.minimum
                            }
                            let hasAudioEnergy = normalized.contains { $0 > Self.activityThreshold }
                            self.updateAudioActivity(hasAudioEnergy)
                            if !self.isPlaying, hasAudioEnergy {
                                self.playbackActivityHandler?()
                            }
                            guard self.isPlaying, self.waveformPresentationEnabled else { return }
                            if (hasAudioEnergy || self.isAudioActive), self.waveformLevels != normalized {
                                self.waveformLevels = normalized
                            }
                        }
                    } failure: { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == generation else { return }
                            self.captureFailed = true; self.wantsCapture = false
                            self.status = .unavailable; self.waveformLevels = Self.staticLevels
                            self.setAudioActive(false, notifyIfUnchanged: true)
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
                    self.setAudioActive(false, notifyIfUnchanged: true)
                    return
                }
            }
        }
    }

    private func updateAudioActivity(_ hasAudioEnergy: Bool) {
        guard hasAudioEnergy else { return }
        setAudioActive(true)
        activityGeneration &+= 1
        guard inactivityTask == nil else { return }
        let clock = activityClock
        inactivityTask = Task { [weak self] in
            guard let self else { return }
            var observedGeneration = self.activityGeneration
            while !Task.isCancelled {
                do { try await clock.sleep(for: Self.activityTimeout) }
                catch { return }
                guard !Task.isCancelled else { return }
                if self.activityGeneration != observedGeneration {
                    observedGeneration = self.activityGeneration
                    continue
                }
                self.inactivityTask = nil
                self.setAudioActive(false)
                return
            }
        }
    }

    private func setAudioActive(_ active: Bool, notifyIfUnchanged: Bool = false) {
        if !active {
            inactivityTask?.cancel()
            inactivityTask = nil
            activityGeneration &+= 1
            if waveformLevels != Self.staticLevels { waveformLevels = Self.staticLevels }
        }
        guard isAudioActive != active else {
            // A failed tap must also cancel a session's silent presentation grace.
            if notifyIfUnchanged { localAudioActivityHandler?(active) }
            return
        }
        isAudioActive = active
        localAudioActivityHandler?(active)
    }
}
