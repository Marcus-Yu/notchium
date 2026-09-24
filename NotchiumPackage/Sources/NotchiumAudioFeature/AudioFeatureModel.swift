import AppKit
import Darwin
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import SwiftUI

@MainActor
@Observable
public final class AudioFeatureModel: NotchAudioRendering {
    public private(set) var devices = AudioDevicesSnapshot(availability: .available)
    public private(set) var processes: [AudioProducingProcess] = []
    public private(set) var displayVolume: Double?
    public private(set) var errorMessage: String?
    public private(set) var mixerStatus: AppAudioMixerStatus = .inactive
    public var onHUD: ((NotchAudioHUD) -> Void)?

    @ObservationIgnored private let deviceService: any AudioDevicesService
    @ObservationIgnored private let processService: any AudioProcessesService
    @ObservationIgnored private let mixerService: any AppAudioMixerService
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var deviceTask: Task<Void, Never>?
    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var volumeTask: Task<Void, Never>?
    @ObservationIgnored private var mixerTask: Task<Void, Never>?
    @ObservationIgnored private var hasReceivedDevices = false
    @ObservationIgnored private var isEditingVolume = false
    @ObservationIgnored private var mixerGeneration = 0
    @ObservationIgnored private var applicationCache: [pid_t: NSRunningApplication] = [:]
    private var pinnedBundles: Set<String>
    private var appVolumes: [String: Double]
    private var mutedBundles: Set<String>

    public init(devices: any AudioDevicesService, processes: any AudioProcessesService,
                mixer: any AppAudioMixerService, preferences: UserDefaults = .standard) {
        deviceService = devices
        processService = processes
        mixerService = mixer
        self.preferences = preferences
        pinnedBundles = Set(preferences.stringArray(forKey: "audio.pinnedBundles") ?? [])
        appVolumes = preferences.dictionary(forKey: "audio.appVolumes") as? [String: Double] ?? [:]
        mutedBundles = Set(preferences.stringArray(forKey: "audio.mutedBundles") ?? [])
    }

    public func start() {
        guard deviceTask == nil else { return }
        mixerTask?.cancel(); mixerTask = nil
        deviceTask = Task { [weak self, deviceService] in
            let updates = await deviceService.updates()
            for await snapshot in updates {
                guard let self, !Task.isCancelled else { break }
                self.receive(snapshot)
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
        deviceTask?.cancel(); deviceTask = nil
        processTask?.cancel(); processTask = nil
        volumeTask?.cancel(); volumeTask = nil
        mixerTask?.cancel(); mixerTask = nil
        processes = []
        applicationCache = [:]
        hasReceivedDevices = false
        isEditingVolume = false
        displayVolume = nil
        mixerGeneration &+= 1
        mixerStatus = .inactive
        mixerTask = Task { [mixerService] in
            guard !Task.isCancelled else { return }
            await mixerService.stop()
        }
    }

    public func setPageVisible(_ visible: Bool) {
        // Rendering visibility is intentionally separate from the lightweight process listener.
    }

    func receive(_ next: AudioDevicesSnapshot) {
        let old = devices.currentOutput
        devices = next
        if old?.id != next.currentOutput?.id || next.currentOutput?.volume == nil {
            displayVolume = nil
        } else if !isEditingVolume, let shown = displayVolume, let confirmed = next.currentOutput?.volume,
                  abs(shown - confirmed) < 0.02 {
            displayVolume = nil
        }
        if old?.id != next.currentOutput?.id { reconcileMixer() }
        guard hasReceivedDevices else { hasReceivedDevices = true; return }
        guard let current = next.currentOutput else { return }
        if old?.id != current.id {
            onHUD?(NotchAudioHUD(kind: .outputChanged, deviceName: current.name,
                                 volume: current.volume, isMuted: current.isMuted ?? false))
        } else if old?.volume != current.volume || old?.isMuted != current.isMuted {
            onHUD?(NotchAudioHUD(kind: .volume, deviceName: current.name,
                                 volume: current.volume, isMuted: current.isMuted ?? false))
        }
    }

    public func select(_ device: AudioDevice) {
        Task { [weak self, deviceService] in
            do {
                try await deviceService.selectOutput(id: device.id)
                self?.errorMessage = nil
            } catch { self?.errorMessage = "Could not switch output." }
        }
    }

    public func changeVolume(_ value: Double, finished: Bool = false) {
        guard let current = devices.currentOutput else { return }
        displayVolume = value
        volumeTask?.cancel()
        volumeTask = Task { [weak self, deviceService] in
            if !finished {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            do {
                try await deviceService.setVolume(value, deviceID: current.id)
                self?.errorMessage = nil
            } catch {
                self?.displayVolume = nil
                self?.errorMessage = "This output does not expose volume control."
            }
        }
    }

    public func setVolumeEditing(_ editing: Bool) { isEditingVolume = editing }

    public func toggleMute() {
        guard let current = devices.currentOutput, let muted = current.isMuted else { return }
        Task { [weak self, deviceService] in
            do {
                try await deviceService.setMuted(!muted, deviceID: current.id)
                self?.errorMessage = nil
            } catch { self?.errorMessage = "This output does not expose mute control." }
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

    func receiveProcesses(_ processes: [AudioProducingProcess]) {
        self.processes = processes
        applicationCache = Dictionary(uniqueKeysWithValues: processes.compactMap { process in
            owningApplication(for: process).map { (process.id, $0) }
        })
        reconcileMixer()
    }

    public func openAudioPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func reconcileMixer(debounce: Bool = false) {
        mixerTask?.cancel()
        mixerGeneration &+= 1
        let generation = mixerGeneration
        let targets = processes.filter(hasControllableRoute).compactMap { process -> AppAudioMixTarget? in
            guard let settingsID = settingsBundleID(for: process) else { return nil }
            return AppAudioMixTarget(processID: process.id,
                                     bundleID: process.bundleID ?? settingsID,
                                     volume: appVolumes[settingsID, default: 1],
                                     isMuted: mutedBundles.contains(settingsID))
        }
        let outputID = devices.currentOutput?.id
        mixerTask = Task { [weak self, mixerService] in
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
        return processes.filter {
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
