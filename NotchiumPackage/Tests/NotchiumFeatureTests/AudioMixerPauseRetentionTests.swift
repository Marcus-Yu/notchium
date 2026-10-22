import AppKit
import NotchiumCore
@testable import NotchiumAudioFeature
import NotchiumServices
import XCTest

@MainActor
final class AudioMixerPauseRetentionTests: XCTestCase {
    func testMissingAudioClientRemainsAdjustableAfterNinetySeconds() async {
        let clock = testClock()
        let (retention, updates) = observedRetention(clock: clock)
        defer { retention.reset() }
        let process = player()
        XCTAssertTrue(process.isRunningOutput, "Existing service clients are active by default")
        retention.receive([process], retainingMissing: { _ in true })

        retention.receive([], retainingMissing: { _ in true })
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(90))
        await drainMainActorTasks()

        XCTAssertEqual(updates.current.map(\.id), [process.id])
        XCTAssertFalse(updates.current[0].isRunningOutput)
        XCTAssertEqual(updates.current[0].controllableOutputDeviceIDs, ["7"])
        XCTAssertEqual(updates.current[0].bundleID, process.bundleID)
    }

    func testRowExpiresAtThreeMinutesAndDoesNotReappearFromAnotherEmptySnapshot() async {
        let clock = testClock()
        let (retention, updates) = observedRetention(clock: clock)
        defer { retention.reset() }
        retention.receive([player()], retainingMissing: { _ in true })
        retention.receive([], retainingMissing: { _ in true })
        await clock.waitForPendingSleeps()

        await clock.advance(by: .seconds(179))
        await drainMainActorTasks()
        XCTAssertEqual(updates.current.count, 1)
        await clock.advance(by: .seconds(1))
        await waitUntil { updates.current.isEmpty }
        XCTAssertTrue(updates.current.isEmpty)

        retention.receive([], retainingMissing: { _ in true })
        await drainMainActorTasks()
        XCTAssertTrue(updates.current.isEmpty)
        let sleeps = await clock.sleepHistory()
        XCTAssertEqual(sleeps, [.seconds(180)])
    }

    func testRepeatedInactiveSnapshotsDoNotExtendTheOriginalDeadline() async {
        let clock = testClock()
        let (retention, updates) = observedRetention(clock: clock)
        defer { retention.reset() }
        retention.receive([player()], retainingMissing: { _ in true })
        retention.receive([], retainingMissing: { _ in true })
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(90))

        retention.receive([], retainingMissing: { _ in true })
        await clock.advance(by: .seconds(89))
        await drainMainActorTasks()
        XCTAssertEqual(updates.current.count, 1)
        retention.receive([], retainingMissing: { _ in true })
        await clock.advance(by: .seconds(1))
        await waitUntil { updates.current.isEmpty }

        XCTAssertTrue(updates.current.isEmpty)
        let sleeps = await clock.sleepHistory()
        XCTAssertEqual(sleeps.count, 1, "HAL updates must not restart the pause grace")
    }

    func testResumingThenPausingStartsAFreshThreeMinuteGrace() async {
        let clock = testClock()
        let (retention, updates) = observedRetention(clock: clock)
        defer { retention.reset() }
        let process = player()
        retention.receive([process], retainingMissing: { _ in true })
        retention.receive([], retainingMissing: { _ in true })
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(90))

        retention.receive([process], retainingMissing: { _ in true })
        XCTAssertTrue(updates.current[0].isRunningOutput)
        retention.receive([], retainingMissing: { _ in true })
        await waitForSleepRequests(2, clock: clock)
        await clock.advance(by: .seconds(90))
        await drainMainActorTasks()
        XCTAssertEqual(updates.current.count, 1, "The first pause's deadline cannot end the second pause")
        await clock.advance(by: .seconds(89))
        await drainMainActorTasks()
        XCTAssertEqual(updates.current.count, 1)
        await clock.advance(by: .seconds(1))
        await waitUntil { updates.current.isEmpty }
        XCTAssertTrue(updates.current.isEmpty)
    }

    func testLateCancelledExpiryCannotRemoveAResumedProcess() async {
        let clock = PauseRetentionLateClock()
        let (retention, updates) = observedRetention(clock: clock)
        defer { retention.reset() }
        let process = player()
        retention.receive([process], retainingMissing: { _ in true })
        retention.receive([], retainingMissing: { _ in true })
        await clock.waitForSleep()

        retention.receive([process], retainingMissing: { _ in true })
        await clock.releaseAll()
        await drainMainActorTasks()

        XCTAssertEqual(updates.current, [process])
    }

    func testApplicationExitRemovesRetainedProcessImmediately() async {
        let clock = PauseRetentionLateClock()
        let (retention, updates) = observedRetention(clock: clock)
        defer { retention.reset() }
        let process = player()
        retention.receive([process], retainingMissing: { _ in true })
        retention.receive([], retainingMissing: { _ in true })
        await clock.waitForSleep()

        retention.remove(processIDs: [process.id])

        XCTAssertTrue(updates.current.isEmpty)
        await clock.releaseAll()
        await drainMainActorTasks()
        XCTAssertTrue(updates.current.isEmpty)
    }

    func testMissingProcessWithoutALivingOwnerIsRemovedImmediately() {
        let (retention, updates) = observedRetention(clock: testClock())
        defer { retention.reset() }
        retention.receive([player()], retainingMissing: { _ in true })

        retention.receive([], retainingMissing: { _ in false })

        XCTAssertTrue(updates.current.isEmpty)
    }

    func testResetDiscardsRetentionAndInvalidatesAnOldExpiry() async {
        let clock = PauseRetentionLateClock()
        let (retention, updates) = observedRetention(clock: clock)
        defer { retention.reset() }
        let first = player()
        retention.receive([first], retainingMissing: { _ in true })
        retention.receive([], retainingMissing: { _ in true })
        await clock.waitForSleep()

        retention.reset()
        let next = player(id: 22)
        retention.receive([next], retainingMissing: { _ in true })
        await clock.releaseAll()
        await drainMainActorTasks()

        XCTAssertEqual(updates.current, [next])
    }

    func testEachAppHasItsOwnPauseDeadline() async {
        let clock = testClock()
        let (retention, updates) = observedRetention(clock: clock)
        defer { retention.reset() }
        let first = player(id: 21)
        let second = player(id: 22)
        retention.receive([first, second], retainingMissing: { _ in true })
        retention.receive([second], retainingMissing: { _ in true })
        await clock.waitForPendingSleeps()
        XCTAssertEqual(updates.current.map(\.isRunningOutput), [false, true])
        await clock.advance(by: .seconds(90))
        retention.receive([], retainingMissing: { _ in true })
        await waitForSleepRequests(2, clock: clock)
        XCTAssertEqual(updates.current.map(\.isRunningOutput), [false, false])

        await clock.advance(by: .seconds(90))
        await waitUntil { updates.current.map(\.id) == [second.id] }
        XCTAssertEqual(updates.current.map(\.id), [second.id])
        await clock.advance(by: .seconds(90))
        await waitUntil { updates.current.isEmpty }
        XCTAssertTrue(updates.current.isEmpty)
    }

    func testExplicitInactiveSnapshotRetainsOnlyPreviouslyAudibleApps() async {
        let clock = testClock()
        let (retention, updates) = observedRetention(clock: clock)
        defer { retention.reset() }
        let active = player()
        let paused = player(isRunningOutput: false)
        let neverPlayed = player(id: 22, isRunningOutput: false)
        retention.receive([active], retainingMissing: { _ in true })

        retention.receive([paused, neverPlayed], retainingMissing: { _ in true })
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(179))
        await drainMainActorTasks()

        XCTAssertEqual(updates.current, [paused])
        await clock.advance(by: .seconds(1))
        await waitUntil { updates.current.isEmpty }
        retention.receive([paused, neverPlayed], retainingMissing: { _ in true })
        XCTAssertTrue(updates.current.isEmpty, "Inactive HAL clients cannot revive expired rows")
    }

    func testPausedRowAcceptsSavedVolumeAtNinetySecondsWithoutStartingATapUntilResume() async throws {
        let finder = try runningFinder()
        let suite = "AudioMixerPauseRetentionTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let clock = testClock()
        let mixer = PauseRetentionObservedMixer()
        let model = AudioFeatureModel(devices: MockAudioDevicesService(),
                                      processes: MockAudioProcessesService(), mixer: mixer,
                                      preferences: preferences, clock: clock)
        defer {
            model.stop()
            preferences.removePersistentDomain(forName: suite)
        }
        let process = AudioProducingProcess(id: finder.processIdentifier, bundleID: "com.apple.finder",
                                            controllableOutputDeviceIDs: ["7"])
        model.receive(.init(availability: .available, outputs: [
            .init(id: "7", name: "Speakers", isDefaultOutput: true)
        ]))
        model.receiveProcesses([process])
        model.setAppVolume(0.6, process: process)
        model.commitAppVolume(process)
        await waitForMixer(mixer) { $0 == [AppAudioMixTarget(processID: process.id,
            bundleID: "com.apple.finder", volume: 0.6, isMuted: false)] }

        model.receiveProcesses([])
        await clock.waitForPendingSleeps()
        await waitForMixer(mixer) { $0.isEmpty }
        await clock.advance(by: .seconds(90))
        let retained = try XCTUnwrap(model.visibleProcesses.first)
        XCTAssertEqual(retained.id, process.id)
        XCTAssertFalse(retained.isRunningOutput)

        let applyCount = await mixer.applyCount
        model.setAppVolume(0.2, process: retained)
        model.commitAppVolume(retained)
        await waitForMixerApply(after: applyCount, mixer: mixer)
        XCTAssertEqual(model.appVolume(retained), 0.2, accuracy: 0.001)
        let pausedTargets = await mixer.targets
        XCTAssertTrue(pausedTargets.isEmpty, "Retained controls must not tap an inactive process")
        XCTAssertEqual(preferences.dictionary(forKey: "audio.appVolumes")?["com.apple.finder"] as? Double, 0.2)

        model.receiveProcesses([process])
        await waitForMixer(mixer) { $0 == [AppAudioMixTarget(processID: process.id,
            bundleID: "com.apple.finder", volume: 0.2, isMuted: false)] }
        XCTAssertTrue(try XCTUnwrap(model.visibleProcesses.first).isRunningOutput)
    }

    func testApplicationTerminationRemovesThePausedModelRowBeforeGraceExpires() async throws {
        let finder = try runningFinder()
        let clock = testClock()
        let model = AudioFeatureModel(devices: MockAudioDevicesService(),
                                      processes: MockAudioProcessesService(), mixer: MockAppAudioMixerService(),
                                      clock: clock)
        defer { model.stop() }
        model.receive(.init(availability: .available, outputs: [
            .init(id: "7", name: "Speakers", isDefaultOutput: true)
        ]))
        model.receiveProcesses([AudioProducingProcess(id: finder.processIdentifier,
            bundleID: "com.apple.finder", controllableOutputDeviceIDs: ["7"])])
        model.receiveProcesses([])
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(90))
        XCTAssertEqual(model.visibleProcesses.count, 1)

        model.applicationDidTerminate(processID: finder.processIdentifier)

        XCTAssertTrue(model.visibleProcesses.isEmpty)
        XCTAssertTrue(model.processes.isEmpty)
    }

    private func player(id: Int32 = 21, isRunningOutput: Bool = true) -> AudioProducingProcess {
        .init(id: id, bundleID: "com.example.player.\(id)",
              controllableOutputDeviceIDs: ["7"], isRunningOutput: isRunningOutput)
    }

    private func testClock() -> TestAppClock {
        TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
    }

    private func observedRetention(clock: any AppClock) -> (AudioMixerProcessRetention, PauseRetentionUpdates) {
        let updates = PauseRetentionUpdates()
        let retention = AudioMixerProcessRetention(clock: clock)
        retention.onChange = { updates.current = $0 }
        return (retention, updates)
    }

    private func runningFinder() throws -> NSRunningApplication {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            throw XCTSkip("A running Finder instance is needed to exercise ownership-based mixer visibility")
        }
        return finder
    }

    private func waitForSleepRequests(_ count: Int, clock: TestAppClock) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await clock.sleepHistory().count < count, ContinuousClock.now < deadline {
            await Task.yield()
        }
        let requested = await clock.sleepHistory().count
        XCTAssertGreaterThanOrEqual(requested, count, "Wait for fake-clock registration before advancing")
    }

    private func waitForMixer(_ mixer: PauseRetentionObservedMixer,
                              matching expected: ([AppAudioMixTarget]) -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await expected(mixer.targets)), ContinuousClock.now < deadline {
            await Task.yield()
        }
        let targets = await mixer.targets
        XCTAssertTrue(expected(targets), "Wait for the mixer service's actual applied target list")
    }

    private func waitForMixerApply(after count: Int, mixer: PauseRetentionObservedMixer) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await mixer.applyCount <= count, ContinuousClock.now < deadline {
            await Task.yield()
        }
        let applied = await mixer.applyCount
        XCTAssertGreaterThan(applied, count)
    }
}

@MainActor
private final class PauseRetentionUpdates {
    var current: [AudioProducingProcess] = []
}

/// Deliberately finishes sleep after cancellation to exercise stale-task protection.
private actor PauseRetentionLateClock: AppClock {
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []

    func now() -> Date { Date(timeIntervalSince1970: 0) }

    func sleep(for duration: Duration) async throws {
        await withCheckedContinuation { continuation in
            sleepers.append(continuation)
            let waiting = observers
            observers.removeAll()
            waiting.forEach { $0.resume() }
        }
    }

    func waitForSleep() async {
        guard sleepers.isEmpty else { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func releaseAll() {
        let pending = sleepers
        sleepers.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor PauseRetentionObservedMixer: AppAudioMixerService {
    private(set) var targets: [AppAudioMixTarget] = []
    private(set) var applyCount = 0

    func apply(targets: [AppAudioMixTarget], outputDeviceID: String?) -> AppAudioMixerStatus {
        self.targets = targets.filter { $0.isMuted || $0.volume < 0.999 }
        applyCount += 1
        return self.targets.isEmpty ? .inactive : .running
    }

    func stop() { targets = [] }
}
