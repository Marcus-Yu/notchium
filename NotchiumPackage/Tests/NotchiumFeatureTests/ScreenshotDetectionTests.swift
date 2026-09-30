import Foundation
import XCTest
@testable import NotchiumServices

/// The real detection path on this machine: macOS's own screencapture writes a file, the
/// real service's folder watch and attribute check must report exactly one capture.
@MainActor
final class ScreenshotDetectionTests: XCTestCase {
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
