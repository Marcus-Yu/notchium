import AppKit
import NotchiumCore
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
    public var onHUD: ((NotchAudioHUD) -> Void)?

    @ObservationIgnored private let deviceService: any AudioDevicesService
    @ObservationIgnored private let processService: any AudioProcessesService
    @ObservationIgnored private var deviceTask: Task<Void, Never>?
    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var volumeTask: Task<Void, Never>?
    @ObservationIgnored private var hasReceivedDevices = false
    @ObservationIgnored private var isEditingVolume = false
    private var pinnedBundles: Set<String>

    public init(devices: any AudioDevicesService, processes: any AudioProcessesService) {
        deviceService = devices
        processService = processes
        pinnedBundles = Set(UserDefaults.standard.stringArray(forKey: "audio.pinnedBundles") ?? [])
    }

    public func start() {
        guard deviceTask == nil else { return }
        deviceTask = Task { [weak self, deviceService] in
            let updates = await deviceService.updates()
            for await snapshot in updates {
                guard let self, !Task.isCancelled else { break }
                self.receive(snapshot)
            }
        }
    }

    public func stop() {
        deviceTask?.cancel(); deviceTask = nil
        processTask?.cancel(); processTask = nil
        volumeTask?.cancel(); volumeTask = nil
        processes = []
        hasReceivedDevices = false
        isEditingVolume = false
        displayVolume = nil
    }

    public func setPageVisible(_ visible: Bool) {
        guard visible else {
            processTask?.cancel(); processTask = nil
            processes = []
            return
        }
        guard processTask == nil else { return }
        processTask = Task { [weak self, processService] in
            let updates = await processService.updates()
            for await processes in updates {
                guard let self, !Task.isCancelled else { break }
                self.processes = processes
            }
        }
    }

    private func receive(_ next: AudioDevicesSnapshot) {
        let old = devices.currentOutput
        devices = next
        if old?.id != next.currentOutput?.id || next.currentOutput?.volume == nil {
            displayVolume = nil
        } else if !isEditingVolume, let shown = displayVolume, let confirmed = next.currentOutput?.volume,
                  abs(shown - confirmed) < 0.02 {
            displayVolume = nil
        }
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
            }
            catch { self?.errorMessage = "Could not switch output." }
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
            }
            catch {
                self?.displayVolume = nil
                self?.errorMessage = "This output does not expose volume control."
            }
        }
    }

    public func setVolumeEditing(_ editing: Bool) {
        isEditingVolume = editing
    }

    public func toggleMute() {
        guard let current = devices.currentOutput, let muted = current.isMuted else { return }
        Task { [weak self, deviceService] in
            do {
                try await deviceService.setMuted(!muted, deviceID: current.id)
                self?.errorMessage = nil
            }
            catch { self?.errorMessage = "This output does not expose mute control." }
        }
    }

    public func isPinned(_ process: AudioProducingProcess) -> Bool {
        process.bundleID.map(pinnedBundles.contains) ?? false
    }

    public func togglePin(_ process: AudioProducingProcess) {
        guard let bundle = process.bundleID else { return }
        if !pinnedBundles.insert(bundle).inserted { pinnedBundles.remove(bundle) }
        UserDefaults.standard.set(pinnedBundles.sorted(), forKey: "audio.pinnedBundles")
    }

    public var visibleProcesses: [AudioProducingProcess] {
        processes.filter { NSRunningApplication(processIdentifier: $0.id)?.activationPolicy == .regular }
            .sorted { a, b in
                if isPinned(a) != isPinned(b) { return isPinned(a) }
                return appName(a).localizedStandardCompare(appName(b)) == .orderedAscending
            }
    }

    public func appName(_ process: AudioProducingProcess) -> String {
        NSRunningApplication(processIdentifier: process.id)?.localizedName
            ?? process.bundleID?.components(separatedBy: ".").last ?? "Audio App"
    }

    public func appIcon(_ process: AudioProducingProcess) -> NSImage? {
        NSRunningApplication(processIdentifier: process.id)?.icon
    }

    public func activate(_ process: AudioProducingProcess) {
        NSRunningApplication(processIdentifier: process.id)?.activate()
    }

    public func expandedAudio() -> AnyView { AnyView(AudioPageView(model: self)) }
}
