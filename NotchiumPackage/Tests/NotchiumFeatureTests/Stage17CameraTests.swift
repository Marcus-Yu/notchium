import AppKit
import Foundation
import NotchiumCore
import XCTest
@testable import NotchiumCameraFeature
@testable import NotchiumDynamicIsland
@testable import NotchiumServices

@MainActor
final class Stage17CameraTests: XCTestCase {
    func testCollapsingOrRemovingOneDisplayKeepsAnotherPreviewAlive() async {
        let service = MockCameraService()
        let model = CameraModel(service: service, preferences: defaults())
        defer { model.stop() }
        model.openPreview()
        model.setPreviewVisible(true, source: "builtIn")
        model.setPreviewVisible(false, source: "external")
        XCTAssertTrue(model.isPreviewPresented)
        model.setPreviewVisible(true, source: "external")
        model.setPreviewVisible(false, source: "builtIn")
        XCTAssertTrue(model.isPreviewPresented)
        model.setPreviewVisible(false, source: "external")
        XCTAssertFalse(model.isPreviewPresented)
        XCTAssertEqual(model.status, .idle)
    }

    private let builtIn = CameraDevice(id: "built-in", name: "FaceTime HD Camera")
    private let external = CameraDevice(id: "usb", name: "Studio Display Camera")

    func testFirstUseAsksThenStartsAndClosingReleasesTheCamera() async {
        let service = MockCameraService(authorization: .notDetermined)
        let model = CameraModel(service: service, preferences: defaults())
        model.togglePreview()
        XCTAssertTrue(model.isPreviewPresented)
        XCTAssertEqual(model.status, .needsPermission)
        XCTAssertFalse(service.isRunning, "No capture before permission")

        model.requestAccess()
        await waitUntil { model.status == .live }
        XCTAssertTrue(service.isRunning)
        XCTAssertEqual(model.activeDevice, builtIn)
        XCTAssertNotNil(service.makePreviewLayer())

        model.togglePreview()
        XCTAssertFalse(model.isPreviewPresented)
        XCTAssertFalse(service.isRunning, "Closing stops capture immediately")
        XCTAssertEqual(service.stopCount, 1)
        XCTAssertNil(service.makePreviewLayer())
        XCTAssertEqual(model.status, .idle)
    }

    func testDeniedPermissionShowsRecoveryAndNeverCaptures() async {
        let refused = MockCameraService(authorization: .notDetermined, grantsAccess: false)
        let model = CameraModel(service: refused, preferences: defaults())
        model.openPreview()
        model.requestAccess()
        await waitUntil { model.status == .denied }
        XCTAssertFalse(refused.isRunning)

        let denied = CameraModel(service: MockCameraService(authorization: .denied), preferences: defaults())
        denied.openPreview()
        XCTAssertEqual(denied.status, .denied)
    }

    func testMirrorUsesRegularSizeAndClosingRestoresTeleprompter() {
        let camera = CameraModel(service: MockCameraService(authorization: .denied), preferences: defaults())
        let presentation = DynamicIslandPresentationModel()
        presentation.cameraController = camera
        presentation.present(.expanded, animated: false)
        presentation.pageModel.selectedPage = .teleprompter
        defer { presentation.reset() }

        let readerSize = ExpandedNotchLayout.size(for: .teleprompter)
        XCTAssertNotEqual(readerSize, ExpandedNotchLayout.size)
        XCTAssertEqual(presentation.expandedContentSize, readerSize)

        camera.togglePreview(source: presentation.cameraPresentationSource)
        XCTAssertTrue(camera.isPreviewPresented)
        XCTAssertEqual(presentation.expandedContentSize, ExpandedNotchLayout.size)
        XCTAssertEqual(presentation.pageModel.selectedPage, .teleprompter)

        camera.closePreview()
        XCTAssertEqual(presentation.expandedContentSize, readerSize)
    }

    func testCollapsingTheNotchStopsTheSession() async {
        let service = MockCameraService()
        let model = CameraModel(service: service, preferences: defaults())
        let presentation = DynamicIslandPresentationModel(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { presentation.reset() }
        presentation.cameraController = model
        presentation.present(.expanded, animated: false)
        model.togglePreview(source: presentation.cameraPresentationSource)
        await waitUntil { service.isRunning }
        presentation.collapse()
        XCTAssertFalse(model.isPreviewPresented)
        XCTAssertFalse(service.isRunning, "Capture stops as closing begins, not after the animation")
    }

    func testClosingWhileStartingReleasesTheLateSession() async {
        let service = MockCameraService()
        service.startDelay = .milliseconds(30)
        let model = CameraModel(service: service, preferences: defaults())
        model.openPreview()
        await waitUntil { model.status == .starting }
        try? await Task.sleep(for: .milliseconds(5))
        model.closePreview()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(model.status, .idle)

        model.openPreview()
        model.closePreview()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(service.isRunning, "Closed before the start ran: it never starts")
    }

    func testPageNavigationStopsCaptureWithoutCollapsingTheNotch() async {
        for state in [NotchStableState.hovered, .expanded] {
            for swipe in [false, true] {
                let service = MockCameraService()
                let camera = CameraModel(service: service, preferences: defaults())
                let presentation = DynamicIslandPresentationModel(phase: state == .hovered ? .hovered : .expanded)
                defer { presentation.reset(); camera.stop() }
                presentation.cameraController = camera
                camera.togglePreview(source: presentation.cameraPresentationSource)
                await waitUntil { camera.status == .live }

                if swipe { presentation.pageModel.moveSelection(forward: true) }
                else { presentation.pageModel.selectedPage = .calendar }

                XCTAssertEqual(presentation.pageModel.selectedPage, swipe ? .music : .calendar)
                XCTAssertEqual(presentation.visualState, state)
                XCTAssertFalse(camera.isPreviewPresented)
                XCTAssertFalse(service.isRunning)
                XCTAssertEqual(camera.status, .idle)
            }
        }
    }

    func testPageNavigationDuringCameraStartupReleasesTheLateSession() async {
        let service = MockCameraService()
        service.startDelay = .milliseconds(30)
        let camera = CameraModel(service: service, preferences: defaults())
        let presentation = DynamicIslandPresentationModel(phase: .expanded)
        defer { presentation.reset(); camera.stop() }
        presentation.cameraController = camera
        camera.togglePreview(source: presentation.cameraPresentationSource)
        await Task.yield()

        presentation.pageModel.selectedPage = .calendar
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(camera.isPreviewPresented)
        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(camera.status, .idle)
    }

    func testAutomaticOpeningPageOnAnotherDisplayPreservesCameraCapture() async {
        let service = MockCameraService()
        let camera = CameraModel(service: service, preferences: defaults())
        let first = DynamicIslandPresentationModel(phase: .expanded)
        let second = DynamicIslandPresentationModel()
        defer { first.reset(); second.reset(); camera.stop() }
        first.cameraController = camera
        second.cameraController = camera
        camera.togglePreview(source: first.cameraPresentationSource)
        await waitUntil { camera.status == .live }

        second.pageModel.selectedPage = .calendar
        second.present(.expanded, animated: false)
        camera.setPreviewVisible(true, source: second.cameraPresentationSource)
        first.collapse()

        XCTAssertEqual(second.pageModel.selectedPage, .home)
        XCTAssertTrue(camera.isPreviewPresented)
        XCTAssertTrue(service.isRunning)
    }

    func testSwitchingCamerasRestartsOnTheChosenDevice() async {
        let service = MockCameraService(devices: [builtIn, external])
        let model = CameraModel(service: service, preferences: defaults())
        model.openPreview()
        await waitUntil { model.status == .live }
        XCTAssertEqual(model.devices.count, 2)
        model.select(external)
        await waitUntil { model.activeDevice == external }
        XCTAssertEqual(service.startedDevices, ["built-in", "usb"])
        XCTAssertTrue(service.isRunning)

        model.closePreview()
        model.openPreview()
        await waitUntil { model.status == .live }
        XCTAssertEqual(model.activeDevice, external, "The chosen camera is remembered")
    }

    func testDisconnectFallsBackAndReconnectResumes() async {
        let service = MockCameraService(devices: [external, builtIn])
        let model = CameraModel(service: service, preferences: defaults())
        model.openPreview()
        await waitUntil { model.activeDevice == external }
        service.disconnect("usb")
        await waitUntil { model.activeDevice == builtIn }
        XCTAssertEqual(model.status, .live)

        service.disconnect("built-in")
        await waitUntil { model.status == .noCamera }
        XCTAssertFalse(service.isRunning)
        service.connect(builtIn)
        await waitUntil { model.status == .live }
        XCTAssertEqual(model.activeDevice, builtIn)
    }

    func testSleepClosesThePreview() async {
        let service = MockCameraService()
        let model = CameraModel(service: service, preferences: defaults())
        model.openPreview()
        await waitUntil { service.isRunning }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await waitUntil { !model.isPreviewPresented }
        XCTAssertFalse(service.isRunning)
        model.stop()
    }

    func testMirrorDefaultsOnAndPersists() {
        let preferences = defaults()
        let model = CameraModel(service: MockCameraService(), preferences: preferences)
        XCTAssertTrue(model.isMirrored)
        model.isMirrored = false
        XCTAssertFalse(CameraModel(service: MockCameraService(), preferences: preferences).isMirrored)
    }

    private func defaults() -> UserDefaults {
        let name = "notchium.tests.camera.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}
