import AppKit
import NotchiumCore
import XCTest
@testable import NotchiumCameraFeature
@testable import NotchiumDynamicIsland
@testable import NotchiumServices
@testable import NotchiumShelfFeature

@MainActor
final class Stage22LifecycleTests: XCTestCase {
    func testRepeatedMirrorOpenCloseReleasesModelAndCamera() async {
        let service = MockCameraService()
        var model: CameraModel? = CameraModel(service: service, preferences: defaults())
        weak var weakModel = model
        for _ in 0..<100 {
            model?.openPreview()
            await waitUntil { model?.status == .live }
            model?.closePreview()
            XCTAssertFalse(service.isRunning)
        }
        model?.openPreview()
        await waitUntil { model?.status == .live }
        model = nil
        XCTAssertNil(weakModel)
        XCTAssertFalse(service.isRunning)
    }

    func testSharingAndFileDragLevelsRestoreFromCurrentOwners() {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        defer { panel.close() }
        panel.applyNotchWindowBehavior()
        for _ in 0..<100 {
            panel.setAcceptsFileDrags(true)
            panel.setNativeSharingPresented(true, source: "share")
            panel.setNativeSharingPresented(true, source: "airdrop")
            panel.setNativeSharingPresented(false, source: "share")
            XCTAssertEqual(panel.level, .floating)
            panel.setNativeSharingPresented(false, source: "airdrop")
            XCTAssertEqual(panel.level, NotchPanel.fileDragLevel)
            panel.setAcceptsFileDrags(false)
            XCTAssertEqual(panel.level, NotchPanel.restingLevel)
        }
    }
    func testInvalidatedThumbnailCannotReturnToCacheAfterGenerationCompletes() async {
        let gate = ThumbnailGate()
        let cache = NotchThumbnailCache { _, _, _ in await gate.generate() }
        let url = URL(fileURLWithPath: "/tmp/stage22-thumbnail")
        let size = CGSize(width: 32, height: 32)
        let first = Task { await cache.image(for: url, size: size) }
        await gate.waitForRequests(1)
        cache.invalidate(url)
        await gate.release(0)
        _ = await first.value
        let second = Task { await cache.image(for: url, size: size) }
        // An explicit actor barrier gives a completed cache hit the chance to finish.
        await drainMainActorTasks()
        let count = await gate.count
        XCTAssertEqual(count, 2, "An invalidated in-flight result must never repopulate the cache")
        if count == 2 { await gate.release(1) }
        _ = await second.value
    }

    func testThumbnailScaleIsPartOfRepresentationIdentity() async {
        let counter = ThumbnailCounter()
        let cache = NotchThumbnailCache { _, _, _ in
            await counter.increment()
            return NSImage(size: CGSize(width: 8, height: 8))
        }
        let url = URL(fileURLWithPath: "/tmp/stage22-scale")
        _ = await cache.image(for: url, size: CGSize(width: 32, height: 32), scale: 1)
        _ = await cache.image(for: url, size: CGSize(width: 32, height: 32), scale: 2)
        let count = await counter.count
        XCTAssertEqual(count, 2)
    }

    func testThumbnailLRUEvictsOldRepresentationsAtItsBound() async {
        let counter = ThumbnailCounter()
        let cache = NotchThumbnailCache(countLimit: 2) { _, _, _ in
            await counter.increment()
            return NSImage(size: CGSize(width: 8, height: 8))
        }
        let urls = (0..<3).map { URL(fileURLWithPath: "/tmp/stage22-lru-\($0)") }
        for url in urls { _ = await cache.image(for: url, size: CGSize(width: 32, height: 32)) }
        _ = await cache.image(for: urls[2], size: CGSize(width: 32, height: 32))
        _ = await cache.image(for: urls[0], size: CGSize(width: 32, height: 32))
        let count = await counter.count
        XCTAssertEqual(count, 4, "The recent representation is reused; the oldest is regenerated")
    }

    func testRepeatedShelfRestoreBalancesEverySecurityScope() {
        let service = ScopedShelfService()
        let shelf = ShelfModel(service: service)
        shelf.add([service.url])
        for _ in 0..<100 { shelf.restore() }
        shelf.clear()
        XCTAssertEqual(service.acquisitions, service.releases)
    }

    func testCameraSleepObservationSurvivesStopAndReopen() async {
        let service = MockCameraService()
        let model = CameraModel(service: service, preferences: defaults())
        model.stop()
        model.openPreview()
        await waitUntil { model.status == .live }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertFalse(model.isPreviewPresented)
        XCTAssertFalse(service.isRunning)
        model.stop()
    }

    func testCameraRuntimeRecoveryIsBoundedUntilExplicitReopen() async {
        let service = FailingCameraService()
        let model = CameraModel(service: service, preferences: defaults())
        model.openPreview()
        await waitUntil { model.status == .live }
        service.failSession()
        await waitUntil { service.starts == 2 && model.status == .live }
        service.failSession()
        await drainMainActorTasks()
        XCTAssertEqual(model.status, .failed)
        XCTAssertEqual(service.starts, 2)
        XCTAssertFalse(service.isRunning)
        model.closePreview()
        model.openPreview()
        await waitUntil { model.status == .live }
        XCTAssertEqual(service.starts, 3)
        model.stop()
    }

    private func defaults() -> UserDefaults {
        let name = "notchium.stage22.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}

private actor ThumbnailGate {
    private var requests: [CheckedContinuation<NSImage?, Never>] = []
    var count: Int { requests.count }
    func generate() async -> NSImage? {
        await withCheckedContinuation { requests.append($0) }
    }
    func waitForRequests(_ count: Int) async {
        while requests.count < count { await Task.yield() }
    }
    func release(_ index: Int) { requests[index].resume(returning: NSImage(size: CGSize(width: 8, height: 8))) }
}

private actor ThumbnailCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

@MainActor
private final class ScopedShelfService: ShelfService {
    let url = URL(fileURLWithPath: "/tmp/stage22-scoped-file")
    var records: [ShelfRecord] = []
    var acquisitions = 0
    var releases = 0
    func loadRecords() -> [ShelfRecord] { records }
    func saveRecords(_ records: [ShelfRecord]) { self.records = records }
    func reference(for url: URL) -> Data? { Data(url.path.utf8) }
    func resolve(_ reference: Data) -> ResolvedShelfReference? { .init(url: url, isStale: false) }
    func fileExists(_ url: URL) -> Bool { true }
    func startAccessing(_ url: URL) -> Bool { acquisitions += 1; return true }
    func stopAccessing(_ url: URL) { releases += 1 }
}

@MainActor
private final class FailingCameraService: CameraService {
    private let camera = MockCameraService()
    private var handler: (@MainActor (CameraEvent) -> Void)?
    private(set) var starts = 0
    var authorization: CameraAuthorization { camera.authorization }
    var isRunning: Bool { camera.isRunning }
    func requestAccess() async -> Bool { await camera.requestAccess() }
    func devices() -> [CameraDevice] { camera.devices() }
    func start(deviceID: String?) async throws -> CameraDevice {
        starts += 1
        return try await camera.start(deviceID: deviceID)
    }
    func stop() { camera.stop() }
    func makePreviewLayer() -> CALayer? { camera.makePreviewLayer() }
    func setEventHandler(_ handler: (@MainActor (CameraEvent) -> Void)?) { self.handler = handler }
    func failSession() { camera.stop(); handler?(.sessionFailed) }
}
