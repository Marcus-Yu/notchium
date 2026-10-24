import NotchiumCore
import Observation
import SwiftUI

/// Keeps an already-visible local session mounted through a brief track gap.
/// Provider playback truth and audio capture activity remain independent.
@MainActor @Observable
final class CollapsedMediaVisibility {
    private static let remainingSilenceGrace = Duration.seconds(5) - SystemAudioMeter.activityTimeout
    private(set) var isVisible = false
    @ObservationIgnored var didChange: (@MainActor () -> Void)?
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0

    init(clock: any AppClock) { self.clock = clock }
    deinit { silenceTask?.cancel() }

    func update(canPresent: Bool, hasAudio: Bool, canBridgeSilence: Bool) {
        guard canPresent else { reset(); return }
        if hasAudio {
            cancelSilenceTask()
            setVisible(true)
            return
        }
        guard isVisible, canBridgeSilence else { reset(); return }
        // Progress/track snapshots cannot extend the same silent interval indefinitely.
        guard silenceTask == nil else { return }
        let clock = clock
        let revision = revision
        silenceTask = Task { [weak self] in
            do { try await clock.sleep(for: Self.remainingSilenceGrace) }
            catch { return }
            guard !Task.isCancelled, let self, self.revision == revision else { return }
            self.silenceTask = nil
            self.setVisible(false)
        }
    }

    func reset() {
        cancelSilenceTask()
        setVisible(false)
    }

    private func cancelSilenceTask() {
        revision &+= 1
        silenceTask?.cancel()
        silenceTask = nil
    }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        withAnimation(.easeInOut(duration: 0.12)) { isVisible = visible }
        didChange?()
    }
}
