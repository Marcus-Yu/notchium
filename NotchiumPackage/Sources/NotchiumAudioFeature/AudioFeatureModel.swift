import AppKit
import Darwin
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import SwiftUI

@MainActor
@Observable
public final class AudioFeatureModel: NotchAudioRendering {
    public private(set) var devices = AudioDevicesSnapshot(availability: .available)
    /// Normalized, battery-validated projection of `devices` for presentation.
    public private(set) var outputStates: [OutputDeviceState] = []
    public var currentOutputState: OutputDeviceState? { outputStates.first(where: \.isActiveOutput) }
    public func state(for device: AudioDevice) -> OutputDeviceState? {
        outputStates.first { $0.objectID == device.id }
    }
    public private(set) var processes: [AudioProducingProcess] = []
    public private(set) var displayVolume: Double?
    public private(set) var errorMessage: String?
    public private(set) var mixerStatus: AppAudioMixerStatus = .inactive
    public var onHUD: ((NotchAudioHUD) -> Void)?

    @ObservationIgnored private let deviceService: any AudioDevicesService
    @ObservationIgnored private let processService: any AudioProcessesService
    @ObservationIgnored private let mixerService: any AppAudioMixerService
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let processRetention: AudioMixerProcessRetention
    @ObservationIgnored private var applicationTerminationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var deviceTask: Task<Void, Never>?
    @ObservationIgnored private var volumeCommandTask: Task<Void, Never>?
    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var volumeTask: Task<Void, Never>?
    @ObservationIgnored private var mixerTask: Task<Void, Never>?
    @ObservationIgnored private var hasReceivedDevices = false
    @ObservationIgnored private var deviceTransitions = OutputDeviceTransitionTracker()
    @ObservationIgnored private var outputTransitionRevision: UInt64 = 0
    @ObservationIgnored private var isEditingVolume = false
    @ObservationIgnored private var pendingInlineVolumes: [Double] = []
    @ObservationIgnored private var pendingInlineMute: Bool?
    @ObservationIgnored private var mixerGeneration = 0
    @ObservationIgnored private var applicationCache: [pid_t: NSRunningApplication] = [:]
    private var pinnedBundles: Set<String>
    private var appVolumes: [String: Double]
    private var mutedBundles: Set<String>

    public init(devices: any AudioDevicesService, processes: any AudioProcessesService,
                mixer: any AppAudioMixerService, preferences: UserDefaults = .standard,
                clock: any AppClock = ContinuousAppClock(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        deviceService = devices
        processService = processes
        mixerService = mixer
        processRetention = AudioMixerProcessRetention(clock: clock)
        self.preferences = preferences
        pinnedBundles = Set(preferences.stringArray(forKey: "audio.pinnedBundles") ?? [])
        appVolumes = preferences.dictionary(forKey: "audio.appVolumes") as? [String: Double] ?? [:]
        mutedBundles = Set(preferences.stringArray(forKey: "audio.mutedBundles") ?? [])
        processRetention.onChange = { [weak self] processes in
            guard let self else { return }
            self.processes = processes
            let ids = Set(processes.map(\.id))
            self.applicationCache = self.applicationCache.filter { ids.contains($0.key) }
            self.reconcileMixer()
        }
    }

    isolated deinit { removeApplicationTerminationObserver() }

    public func start() {
        guard deviceTask == nil else { return }
        observeApplicationTermination()
        mixerTask?.cancel(); mixerTask = nil
        deviceTask = Task { [weak self, deviceService] in
            let updates = await deviceService.updates()
            for await snapshot in updates {
                guard let self, !Task.isCancelled else { break }
                self.receive(snapshot)
            }
        }
        volumeCommandTask = Task { [weak self, deviceService] in
            let commands = await deviceService.volumeCommands()
            for await event in commands {
                guard let self, !Task.isCancelled else { break }
                self.receiveVolumeCommand(event)
            }
        }
        // Event driven process observation must remain available to enforce persisted gains when
        // an adjusted app becomes audible. No sample metering or SwiftUI work runs while hidden.
        processTask = Task { [weak self, processService] in
            let updates = await processService.updates()
            for await processes in updates {
                guard let self, !Task.isCancelled else { break }
                self.receiveProcesses(processes)
            }
        }
    }

    public func stop() {
        removeApplicationTerminationObserver()
        processRetention.reset()
        deviceTask?.cancel(); deviceTask = nil
        volumeCommandTask?.cancel(); volumeCommandTask = nil
        processTask?.cancel(); processTask = nil
        volumeTask?.cancel(); volumeTask = nil
        let previousMixerTask = mixerTask
        previousMixerTask?.cancel(); mixerTask = nil
        processes = []
        applicationCache = [:]
        hasReceivedDevices = false
        deviceTransitions = OutputDeviceTransitionTracker()
        isEditingVolume = false
        pendingInlineVolumes = []
        pendingInlineMute = nil
        displayVolume = nil
        mixerGeneration &+= 1
        mixerStatus = .inactive
        mixerTask = Task { [mixerService] in
            await previousMixerTask?.value
            guard !Task.isCancelled else { return }
            await mixerService.stop()
        }
    }

    public func setPageVisible(_ visible: Bool) {
        // Rendering visibility is intentionally separate from the lightweight process listener.
    }

    func receive(_ next: AudioDevicesSnapshot) {
        let old = devices.currentOutput
        let oldStates = outputStates
        // HAL echoes the page's own commands through the same stream as hardware keys.
        // Keep their feedback inline, including confirmation arriving after mouse-up.
        let suppressVolumeHUD = consumeInlineVolumeConfirmation(old: old, new: next.currentOutput)
        let suppressMuteHUD = pendingInlineMute.map { $0 == next.currentOutput?.isMuted } ?? false
        devices = next
        let states = next.outputs.map { OutputDeviceState($0, now: now()) }
        if states != outputStates { outputStates = states }
        if old?.id != next.currentOutput?.id || next.currentOutput?.volume == nil {
            volumeTask?.cancel()
            volumeTask = nil
            isEditingVolume = false
            pendingInlineVolumes = []
            pendingInlineMute = nil
            displayVolume = nil
        } else if !isEditingVolume, let shown = displayVolume, let confirmed = next.currentOutput?.volume,
                  abs(shown - confirmed) < 0.02 || old?.volume != confirmed {
            // Outside a drag, a changed device report is authoritative: quantized devices may never
            // land within tolerance, and hardware keys must not be masked by a stale local value.
            displayVolume = nil
        }
        if old?.isMuted != next.currentOutput?.isMuted { pendingInlineMute = nil }
        if old?.id != next.currentOutput?.id { reconcileMixer() }
        // Devices already connected at launch are known state, not events.
        guard hasReceivedDevices else { hasReceivedDevices = true; return }
        if let transition = deviceTransitions.receive(old: oldStates, new: states, now: now()) {
            outputTransitionRevision &+= 1
            onHUD?(transition.hud(revision: outputTransitionRevision))
            return
        }
        guard let current = next.currentOutput, old?.id == current.id else { return }
        if (old?.volume != current.volume && !suppressVolumeHUD)
            || (old?.isMuted != current.isMuted && !suppressMuteHUD) {
            onHUD?(NotchAudioHUD(kind: .volume, deviceName: current.name,
                                 volume: current.volume, isMuted: current.isMuted ?? false))
        }
    }

    public func select(_ device: AudioDevice) {
        // Explicit route selection is distinct from HAL's automatic appearance/route pair.
        // The animation still waits for a confirmed device snapshot, including on failure.
        deviceTransitions.selecting(device.uid ?? device.id)
        Task { [weak self, deviceService] in
            do {
                try await deviceService.selectOutput(id: device.id)
                self?.errorMessage = nil
            } catch { self?.errorMessage = "Could not switch output." }
        }
    }

    /// Hardware intent always wins over inline feedback suppression. In the normal passive
    /// path, interior changes still use HAL updates; boundaries have no changed snapshot.
    func receiveVolumeCommand(_ event: AudioVolumeCommandEvent) {
        let output = event.output
        guard hasReceivedDevices, devices.currentOutput?.id == output.id else { return }
        let overridesInlineFeedback = (!pendingInlineVolumes.isEmpty || pendingInlineMute != nil)
            && (event.command == .mute ? output.canSetMute && output.isMuted != nil
                : output.canSetVolume && output.volume != nil)
        pendingInlineVolumes = []
        pendingInlineMute = nil
        guard event.wasReplaced || overridesInlineFeedback
            || (output.canSetVolume && event.command.isUnchangedBoundary(volume: output.volume)) else { return }
        onHUD?(NotchAudioHUD(kind: .volume, deviceName: output.name,
                             volume: output.volume, isMuted: output.isMuted ?? false))
    }

    public func changeVolume(_ value: Double, finished: Bool = false) {
        guard value.isFinite, let current = devices.currentOutput, current.canSetVolume else { return }
        let value = min(max(value, 0), 1)
        displayVolume = value
        volumeTask?.cancel()
        volumeTask = Task { [weak self, deviceService] in
            if !finished {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            // Register writes only after debounce: cancelled slider values cannot produce
            // HAL echoes. A same-value write with no outstanding change needs no suppression.
            guard self?.devices.currentOutput?.id == current.id else { return }
            if let self {
                let unchanged = self.devices.currentOutput?.volume.map { Float32($0) == Float32(value) } ?? false
                let repeatsPending = self.pendingInlineVolumes.last.map { Float32($0) == Float32(value) } ?? false
                if (!unchanged || !self.pendingInlineVolumes.isEmpty), !repeatsPending {
                    self.pendingInlineVolumes.append(value)
                }
            }
            do {
                try await deviceService.setVolume(value, deviceID: current.id)
                guard !Task.isCancelled, let self, self.devices.currentOutput?.id == current.id else { return }
                self.errorMessage = nil
                self.clearConfirmedVolume()
            } catch {
                guard !Task.isCancelled, let self, self.devices.currentOutput?.id == current.id else { return }
                self.displayVolume = nil
                self.pendingInlineVolumes = []
                self.errorMessage = "This output does not expose volume control."
            }
        }
    }

    public func setVolumeEditing(_ editing: Bool) {
        isEditingVolume = editing
        if !editing { clearConfirmedVolume() }
    }

    private func clearConfirmedVolume() {
        guard !isEditingVolume, let shown = displayVolume,
              let confirmed = devices.currentOutput?.volume,
              abs(shown - confirmed) < 0.02 else { return }
        displayVolume = nil
    }

    private func consumeInlineVolumeConfirmation(old: AudioDevice?, new: AudioDevice?) -> Bool {
        guard old?.id == new?.id, old?.volume != new?.volume, let confirmed = new?.volume else { return false }
        let confirmedScalar = Float32(confirmed)
        // Fine slider steps can be closer than a device's confirmation tolerance. Prefer
        // the first exact HAL scalar so an early echo cannot acknowledge a later close value.
        let exactIndex = pendingInlineVolumes.firstIndex { Float32($0) == confirmedScalar }
        var nearest: (index: Int, distance: Double)?
        if exactIndex == nil {
            for (index, value) in pendingInlineVolumes.enumerated() {
                let distance = abs(Double(Float32(value)) - Double(confirmedScalar))
                guard distance < 0.02 else { continue }
                // Quantized readback uses the nearest request. Equal-distance targets
                // retain submission order instead of consuming a later unconfirmed write.
                if distance + Double(confirmedScalar.ulp) < (nearest?.distance ?? .infinity) {
                    nearest = (index, distance)
                }
            }
        }
        guard let index = exactIndex ?? nearest?.index else {
            // A different HAL value is independent feedback, including hardware keys when
            // passive key observation is unavailable. It ends any obsolete local intent.
            pendingInlineVolumes = []
            return false
        }
        // A bounded stream may coalesce intermediate writes; their latest confirmation
        // acknowledges all earlier submitted values as well.
        pendingInlineVolumes.removeFirst(index + 1)
        return true
    }

    public func toggleMute() {
        guard let current = devices.currentOutput, let muted = current.isMuted else { return }
        let requestedMute = !muted
        pendingInlineMute = requestedMute
        Task { [weak self, deviceService] in
            do {
                try await deviceService.setMuted(requestedMute, deviceID: current.id)
                self?.errorMessage = nil
            } catch {
                if self?.pendingInlineMute == requestedMute { self?.pendingInlineMute = nil }
                self?.errorMessage = "This output does not expose mute control."
            }
        }
    }

    public func isPinned(_ process: AudioProducingProcess) -> Bool {
        settingsBundleID(for: process).map(pinnedBundles.contains) ?? false
    }

    public func togglePin(_ process: AudioProducingProcess) {
        guard let bundle = settingsBundleID(for: process) else { return }
        if !pinnedBundles.insert(bundle).inserted { pinnedBundles.remove(bundle) }
        preferences.set(pinnedBundles.sorted(), forKey: "audio.pinnedBundles")
    }

    public func appVolume(_ process: AudioProducingProcess) -> Double {
        guard let bundleID = settingsBundleID(for: process) else { return 1 }
        return appVolumes[bundleID, default: 1]
    }

    public func isAppMuted(_ process: AudioProducingProcess) -> Bool {
        settingsBundleID(for: process).map(mutedBundles.contains) ?? false
    }

    public func setAppVolume(_ volume: Double, process: AudioProducingProcess) {
        guard let bundleID = settingsBundleID(for: process) else { return }
        let value = min(max(volume, 0), 1)
        if value >= 0.999 { appVolumes[bundleID] = nil } else { appVolumes[bundleID] = value }
        reconcileMixer(debounce: true)
    }

    public func commitAppVolume(_ process: AudioProducingProcess) {
        guard settingsBundleID(for: process) != nil else { return }
        preferences.set(appVolumes, forKey: "audio.appVolumes")
        reconcileMixer()
    }

    public func toggleAppMute(_ process: AudioProducingProcess) {
        guard let bundleID = settingsBundleID(for: process) else { return }
        if !mutedBundles.insert(bundleID).inserted { mutedBundles.remove(bundleID) }
        preferences.set(mutedBundles.sorted(), forKey: "audio.mutedBundles")
        reconcileMixer()
    }

    public func resetAppVolume(_ process: AudioProducingProcess) {
        guard let bundleID = settingsBundleID(for: process) else { return }
        appVolumes[bundleID] = nil
        mutedBundles.remove(bundleID)
        preferences.set(appVolumes, forKey: "audio.appVolumes")
        preferences.set(mutedBundles.sorted(), forKey: "audio.mutedBundles")
        reconcileMixer()
    }

    public func retryMixerPermission() { reconcileMixer() }

    /// The mixer reports denial only once it starts; a denied eligibility probe reports it before.
    public var audioPermissionRequired: Bool {
        mixerStatus == .permissionRequired
            || processes.contains { $0.requiresAudioPermission && isControllable($0) }
    }

    func receiveProcesses(_ processes: [AudioProducingProcess]) {
        for process in processes {
            applicationCache[process.id] = owningApplication(for: process)
        }
        processRetention.receive(processes) { process in
            guard let application = self.applicationCache[process.id] else { return false }
            return !application.isTerminated
        }
    }

    private func observeApplicationTermination() {
        guard applicationTerminationObserver == nil else { return }
        applicationTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let processID = application.processIdentifier
            MainActor.assumeIsolated {
                self?.applicationDidTerminate(processID: processID)
            }
        }
    }

    private func removeApplicationTerminationObserver() {
        if let applicationTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationTerminationObserver)
            self.applicationTerminationObserver = nil
        }
    }

    func applicationDidTerminate(processID: Int32) {
        let ids = Set(applicationCache.compactMap { id, application in
            application.processIdentifier == processID ? id : nil
        })
        processRetention.remove(processIDs: ids)
    }

    public func openAudioPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func reconcileMixer(debounce: Bool = false) {
        let previous = mixerTask
        previous?.cancel()
        mixerGeneration &+= 1
        let generation = mixerGeneration
        let targets = processes.filter { $0.isRunningOutput && hasControllableRoute($0) }
            .compactMap { process -> AppAudioMixTarget? in
                guard let settingsID = settingsBundleID(for: process) else { return nil }
                return AppAudioMixTarget(processID: process.id,
                                         bundleID: process.bundleID ?? settingsID,
                                         volume: appVolumes[settingsID, default: 1],
                                         isMuted: mutedBundles.contains(settingsID))
            }
        let outputID = devices.currentOutput?.id
        mixerTask = Task { [weak self, mixerService] in
            // The mixer runs off the main actor: applies must still land in submission order.
            await previous?.value
            if debounce {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let status = await mixerService.apply(targets: targets, outputDeviceID: outputID)
            guard !Task.isCancelled, let self, generation == self.mixerGeneration else { return }
            self.mixerStatus = status
        }
    }

    public var visibleProcesses: [AudioProducingProcess] {
        var bundles = Set<String>()
        return processes.sorted { $0.isRunningOutput && !$1.isRunningOutput }.filter {
            guard isControllable($0),
                  let bundleID = settingsBundleID(for: $0) else { return false }
            return bundles.insert(bundleID).inserted
        }.sorted { a, b in
            if isPinned(a) != isPinned(b) { return isPinned(a) }
            return appName(a).localizedStandardCompare(appName(b)) == .orderedAscending
        }
    }

    public func appName(_ process: AudioProducingProcess) -> String {
        applicationCache[process.id]?.localizedName
            ?? process.bundleID?.components(separatedBy: ".").last ?? "Audio App"
    }

    public func appIcon(_ process: AudioProducingProcess) -> NSImage? {
        applicationCache[process.id]?.icon
    }

    private func settingsBundleID(for process: AudioProducingProcess) -> String? {
        applicationCache[process.id]?.bundleIdentifier ?? process.bundleID
    }

    private func isControllable(_ process: AudioProducingProcess) -> Bool {
        guard hasControllableRoute(process),
              let application = applicationCache[process.id],
              !application.isTerminated,
              let bundleID = application.bundleIdentifier else { return false }
        return bundleID != Bundle.main.bundleIdentifier
    }

    private func hasControllableRoute(_ process: AudioProducingProcess) -> Bool {
        process.isControllable(on: devices.currentOutput?.id)
            && process.bundleID != Bundle.main.bundleIdentifier
    }

    private func owningApplication(for process: AudioProducingProcess) -> NSRunningApplication? {
        var pid = process.id
        var visited = Set<pid_t>()
        for _ in 0..<10 where pid > 1 && visited.insert(pid).inserted {
            if let application = NSRunningApplication(processIdentifier: pid),
               !application.isTerminated,
               application.activationPolicy == .regular,
               application.bundleIdentifier != nil {
                return application
            }
            guard let parent = Self.parentProcessID(of: pid), parent != pid else { break }
            pid = parent
        }
        return nil
    }

    private static func parentProcessID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let expected = Int32(MemoryLayout.size(ofValue: info))
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected) == expected else { return nil }
        return pid_t(info.pbi_ppid)
    }

    public func expandedAudio() -> AnyView { AnyView(AudioPageView(model: self)) }
}
