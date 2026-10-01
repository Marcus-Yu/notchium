import AppKit
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import SwiftUI

/// The header Mirror utility. Capture runs only while the preview is on screen; closing it,
/// collapsing the notch or sleeping the Mac stops the session and releases the camera.
@MainActor
@Observable
public final class CameraModel {
    public enum Status: Equatable, Sendable {
        case idle, starting, live
        case needsPermission, denied, noCamera, failed
    }

    public private(set) var status: Status = .idle
    public private(set) var isPreviewPresented = false
    public private(set) var devices: [CameraDevice] = []
    public private(set) var activeDevice: CameraDevice?
    /// Mirrored like a mirror by default; "Natural" shows what others see.
    public var isMirrored: Bool {
        didSet { preferences.set(isMirrored, forKey: Keys.mirrored) }
    }

    @ObservationIgnored let service: any CameraService
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let mirrored = "notchium.camera.mirrored.v1"
        static let device = "notchium.camera.device.v1"
    }

    public init(service: any CameraService, preferences: UserDefaults = .standard) {
        self.service = service
        self.preferences = preferences
        isMirrored = preferences.object(forKey: Keys.mirrored) as? Bool ?? true
        service.setEventHandler { [weak self] event in self?.handle(event) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closePreview() }
            })
    }

    public func stop() {
        closePreview()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
    }

    // MARK: Preview lifecycle

    public func togglePreview() {
        isPreviewPresented ? closePreview() : openPreview()
    }

    public func openPreview() {
        guard !isPreviewPresented else { return }
        isPreviewPresented = true
        devices = service.devices()
        switch service.authorization {
        case .authorized: startSession()
        case .notDetermined: status = .needsPermission
        case .denied, .restricted: status = .denied
        }
    }

    /// Stops capture immediately; safe to call repeatedly.
    public func closePreview() {
        generation &+= 1
        service.stop()
        isPreviewPresented = false
        activeDevice = nil
        status = .idle
    }

    /// First use: macOS asks once; a refusal shows the Settings recovery.
    public func requestAccess(completion: @escaping @MainActor () -> Void = {}) {
        let current = generation
        Task { [weak self, service] in
            let granted = await service.requestAccess()
            completion()
            guard let self, current == self.generation, self.isPreviewPresented else { return }
            if granted { self.startSession() } else { self.status = .denied }
        }
    }

    public func select(_ device: CameraDevice) {
        preferences.set(device.id, forKey: Keys.device)
        guard isPreviewPresented, device != activeDevice else { return }
        startSession()
    }

    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startSession() {
        generation &+= 1
        let current = generation
        devices = service.devices()
        guard !devices.isEmpty else {
            service.stop()
            activeDevice = nil
            status = .noCamera
            return
        }
        let preferred = preferences.string(forKey: Keys.device)
        let target = devices.contains { $0.id == preferred } ? preferred : devices.first?.id
        status = .starting
        Task { [weak self, service] in
            // Closed or restarted before this ran: never start.
            guard let self, current == self.generation else { return }
            do {
                let device = try await service.start(deviceID: target)
                // Closed while the session was starting: release it again. A restart's own
                // start replaces this session.
                guard current == self.generation, self.isPreviewPresented else {
                    if !self.isPreviewPresented { service.stop() }
                    return
                }
                self.activeDevice = device
                self.status = .live
            } catch {
                guard current == self.generation else { return }
                self.status = (error as? CameraFailure) == .noCamera ? .noCamera : .failed
            }
        }
    }

    func handle(_ event: CameraEvent) {
        devices = service.devices()
        guard isPreviewPresented, status != .denied, status != .needsPermission else { return }
        switch event {
        case .devicesChanged:
            // The live camera went away (or a camera arrived while none was available): follow it.
            if let activeDevice, devices.contains(activeDevice) { return }
            startSession()
        case .sessionFailed:
            startSession()
        }
    }
}

extension CameraModel: NotchCameraControlling {
    public func preview() -> AnyView { AnyView(CameraPreviewPanel(model: self)) }
}
