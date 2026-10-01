import AVFoundation
import AppKit
import NotchiumCore

public struct CameraDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum CameraAuthorization: Equatable, Sendable {
    case notDetermined, authorized, denied, restricted
}

public enum CameraEvent: Equatable, Sendable {
    /// A camera was connected or disconnected.
    case devicesChanged
    /// The running session stopped on its own (device lost, runtime error).
    case sessionFailed
}

public enum CameraFailure: Error, Equatable {
    case noCamera, cannotOpen
}

/// A preview-only capture session: no outputs, nothing recorded. The session exists only
/// between `start` and `stop`; after `stop` the device is released.
public protocol CameraService: AnyObject, Sendable {
    @MainActor var authorization: CameraAuthorization { get }
    @MainActor func requestAccess() async -> Bool
    @MainActor func devices() -> [CameraDevice]
    @MainActor func start(deviceID: String?) async throws -> CameraDevice
    @MainActor func stop()
    @MainActor var isRunning: Bool { get }
    /// A preview layer bound to the running session, or nil when stopped.
    @MainActor func makePreviewLayer() -> CALayer?
    @MainActor func setEventHandler(_ handler: @escaping @MainActor (CameraEvent) -> Void)
}

public extension CameraService {
    func availability() async -> FeatureAvailability {
        switch await authorization {
        case .authorized: .available
        case .notDetermined: .unavailable(.permissionNotDetermined)
        case .denied: .unavailable(.permissionDenied)
        case .restricted: .unavailable(.permissionRestricted)
        }
    }
}

@MainActor
public final class RealCameraService: CameraService {
    private var session: AVCaptureSession?
    /// `startRunning`/`stopRunning` block; they run off the main thread, in order.
    private let queue = DispatchQueue(label: "notchium.camera.session")
    private var handler: (@MainActor (CameraEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []

    public init() {}

    public var authorization: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    public func devices() -> [CameraDevice] {
        Self.discovery().devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    public var isRunning: Bool { session != nil }

    public func start(deviceID: String?) async throws -> CameraDevice {
        stop()
        let available = Self.discovery().devices
        guard let device = available.first(where: { $0.uniqueID == deviceID })
                ?? AVCaptureDevice.default(for: .video) ?? available.first else { throw CameraFailure.noCamera }
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraFailure.cannotOpen
        }
        session.addInput(input)
        session.commitConfiguration()
        self.session = session
        observe(session)
        let box = SessionBox(session)
        await withCheckedContinuation { continuation in
            queue.async {
                box.session.startRunning()
                continuation.resume()
            }
        }
        return CameraDevice(id: device.uniqueID, name: device.localizedName)
    }

    public func stop() {
        guard let session else { return }
        self.session = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        let box = SessionBox(session)
        queue.async {
            box.session.stopRunning()
            box.session.inputs.forEach(box.session.removeInput)
        }
    }

    public func makePreviewLayer() -> CALayer? {
        guard let session else { return nil }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    public func setEventHandler(_ handler: @escaping @MainActor (CameraEvent) -> Void) {
        self.handler = handler
        guard deviceObservers.isEmpty else { return }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handler?(.devicesChanged) }
            })
        }
    }

    private var deviceObservers: [NSObjectProtocol] = []

    private func observe(_ session: AVCaptureSession) {
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                                                object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handler?(.sessionFailed) }
        })
    }

    private static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified)
    }
}

/// The session is configured on the main actor and only started/stopped on the serial queue.
private struct SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}

/// Test double with an inspectable lifecycle.
@MainActor
public final class MockCameraService: CameraService {
    public var authorization: CameraAuthorization
    public var grantsAccess: Bool
    public var available: [CameraDevice]
    public var failsToStart = false
    /// Simulates a slow device so tests can close the preview mid-start.
    public var startDelay: Duration?
    public private(set) var isRunning = false
    public private(set) var startedDevices: [String] = []
    public private(set) var stopCount = 0
    private var handler: (@MainActor (CameraEvent) -> Void)?

    nonisolated public init(authorization: CameraAuthorization = .authorized, grantsAccess: Bool = true,
                devices: [CameraDevice] = [CameraDevice(id: "built-in", name: "FaceTime HD Camera")]) {
        self.authorization = authorization
        self.grantsAccess = grantsAccess
        available = devices
    }

    public func requestAccess() async -> Bool {
        authorization = grantsAccess ? .authorized : .denied
        return grantsAccess
    }

    public func devices() -> [CameraDevice] { available }

    public func start(deviceID: String?) async throws -> CameraDevice {
        stop()
        if let startDelay { try? await Task.sleep(for: startDelay) }
        if failsToStart { throw CameraFailure.cannotOpen }
        guard let device = available.first(where: { $0.id == deviceID }) ?? available.first else { throw CameraFailure.noCamera }
        isRunning = true
        startedDevices.append(device.id)
        return device
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        stopCount += 1
    }

    public func makePreviewLayer() -> CALayer? { isRunning ? CALayer() : nil }

    public func setEventHandler(_ handler: @escaping @MainActor (CameraEvent) -> Void) { self.handler = handler }

    public func disconnect(_ id: String) {
        available.removeAll { $0.id == id }
        handler?(.devicesChanged)
    }

    public func connect(_ device: CameraDevice) {
        available.append(device)
        handler?(.devicesChanged)
    }
}
