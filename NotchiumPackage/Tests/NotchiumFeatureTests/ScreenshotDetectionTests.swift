import Foundation
import AppKit
import XCTest
@testable import NotchiumServices

/// The real detection path on this machine: macOS's own screencapture writes a file, the
/// real service's folder watch and attribute check must report exactly one capture.
@MainActor
final class ScreenshotDetectionTests: XCTestCase {
    func testLateCaptureAttributeAndWritesAreObservedWithoutRetryDeadline() async throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("polish-shot-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = RealScreenshotService(location: { folder })
        let stream = await service.events()
        var events: [ScreenshotEvent] = []
        let ready = expectation(description: "File write and metadata events produce a ready capture")
        let collector = Task { @MainActor in
            for await event in stream {
                events.append(event)
                if case .captured = event { ready.fulfill() }
            }
        }
        defer { collector.cancel() }
        let url = folder.appendingPathComponent("capture.png")
        try Data().write(to: url)
        // The incomplete candidate is watched; a delayed attribute must still be noticed
        // after the old 3 x 400 ms retry window, independently of Spotlight indexing.
        try await Task.sleep(for: .milliseconds(1600))
        let attribute = Data([1])
        let result = attribute.withUnsafeBytes {
            setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, 0)
        }
        XCTAssertEqual(result, 0)
        let incompleteReady = await RealScreenshotService.isReadyCapture(url)
        XCTAssertFalse(incompleteReady, "Never emit a tagged but incomplete image")
        let image = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        let started = Date()
        try data.write(to: url)
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.75)
        XCTAssertEqual(events.count, 1)
        let completeReady = await RealScreenshotService.isReadyCapture(url)
        XCTAssertTrue(completeReady)
        // More metadata/writes for the same image cannot create another capture.
        try data.write(to: url)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(events.count, 1)
    }

    func testRealScreencaptureFileIsDetectedPromptlyOnce() async throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notchium-shots-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appendingPathComponent("existing.png").path, contents: Data())

        let service = RealScreenshotService(location: { folder })
        let stream = await service.events()
        let access = await service.availability()
        XCTAssertEqual(access, .available)
        var events: [ScreenshotEvent] = []
        let collector = Task { @MainActor in for await event in stream { events.append(event) } }

        let shot = folder.appendingPathComponent("Screenshot 1.png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", shot.path]
        try capture.run()
        capture.waitUntilExit()
        try XCTSkipUnless(FileManager.default.fileExists(atPath: shot.path), "screencapture unavailable here")
        XCTAssertTrue(RealScreenshotService.isScreenCapture(shot), "macOS tags captures with the attribute")

        let started = Date()
        while events.isEmpty, Date().timeIntervalSince(started) < 3 { try await Task.sleep(for: .milliseconds(50)) }
        let latency = Date().timeIntervalSince(started)
        XCTAssertEqual(events, [.captured(.init(fileURL: shot, createdAt: try XCTUnwrap(
            shot.resourceValues(forKeys: [.creationDateKey]).creationDate)))])
        XCTAssertLessThan(latency, 1.5, "Prompt, not Spotlight-delayed")

        // A non-capture file appearing is ignored; deleting the capture reports removal once.
        FileManager.default.createFile(atPath: folder.appendingPathComponent("notes.txt").path, contents: Data())
        try FileManager.default.removeItem(at: shot)
        try await Task.sleep(for: .milliseconds(600))
        collector.cancel()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last, .removed(shot))
    }

    func testConfiguredLocationFallsBackToDesktop() {
        let defaults = UserDefaults(suiteName: "notchium.test.screencapture.\(UUID())")!
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(RealScreenshotService.configuredLocation(defaults: defaults).standardizedFileURL,
                       desktop.standardizedFileURL)
        defaults.set(NSTemporaryDirectory(), forKey: "location")
        XCTAssertEqual(RealScreenshotService.configuredLocation(defaults: defaults).standardizedFileURL,
                       URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL)
        defaults.set("/nonexistent/folder", forKey: "location")
        XCTAssertEqual(RealScreenshotService.configuredLocation(defaults: defaults).standardizedFileURL,
                       desktop.standardizedFileURL)
    }
}
