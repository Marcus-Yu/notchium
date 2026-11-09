import AppKit
import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumPersistence
import NotchiumServices
@testable import NotchiumTeleprompterFeature
import SwiftUI
import XCTest

/// These fixtures render only mock data in an offscreen native window. They never
/// launch the app, start microphone capture, read calendars, or access the real library.
@MainActor
final class TeleprompterRenderingTests: XCTestCase {
    private let pageSize = CGSize(width: ExpandedNotchLayout.teleprompterSize.width,
                                  height: ExpandedNotchLayout.teleprompterSize.height - 70)
    private let editorSize = CGSize(width: 780, height: 500)
    private let destination = URL(fileURLWithPath: "/tmp/notchium-teleprompter-visuals", isDirectory: true)

    func testEmptyReaderAndEditorAtSupportedSizes() async throws {
        let model = await fixture(scripts: [])
        defer { model.stop() }
        XCTAssertNil(model.selectedScript)
        try await renderPage(model, name: "page-empty")
        try await render(TeleprompterEditorView(model: model), name: "editor-empty", size: editorSize)
    }

    func testSavedScriptInEveryScrollingMode() async throws {
        let script = TeleprompterScript(id: fixtureID, title: "Weekly product update",
            text: "Welcome, everyone — here’s our weekly product update.\nRevenue grew 25% to $2.5 million.\nNext: discuss the launch schedule, then answer your questions.")
        let model = await fixture(scripts: [script])
        defer { model.stop() }
        XCTAssertEqual(model.selectedScript?.id, script.id)
        XCTAssertFalse(model.session.alignment.words.isEmpty)
        for mode in TeleprompterMode.allCases {
            model.session.mode = mode
            try await renderPage(model, name: "page-saved-\(mode.rawValue)")
        }
        try await render(TeleprompterEditorView(model: model), name: "editor-saved", size: editorSize)
    }

    func testLongScriptLargeTextAndThreeHundredWordsPerMinute() async throws {
        let paragraph = "Customer retention increased substantially across every region, while our product team prepared the next release and collected feedback from early adopters."
        let script = TeleprompterScript(id: fixtureID,
            title: "Quarterly engineering, customer retention, and international product launch update",
            text: Array(repeating: paragraph, count: 50).joined(separator: "\n\n"))
        let model = await fixture(scripts: [script])
        defer { model.stop() }
        model.session.fontSize = TeleprompterReaderStyle.fontRange.upperBound
        model.session.wordsPerMinute = 300
        model.session.seek(to: 55)
        for mode in TeleprompterMode.allCases {
            model.session.mode = mode
            try await renderPage(model, name: "page-large-\(mode.rawValue)")
        }
        try await render(TeleprompterEditorView(model: model), name: "editor-long", size: editorSize)
    }

    func testSmallerTextAndReducedMotionReader() async throws {
        let model = await fixture(scripts: [.init(id: fixtureID, title: "Declaration",
            text: "In Congress, July 4, 1776\nThe unanimous Declaration of the thirteen united States of America.")])
        defer { model.stop() }
        model.session.fontSize = TeleprompterReaderStyle.fontRange.lowerBound
        try await render(TeleprompterPage(model: model)
            .environment(\.notchReduceMotionOverride, true)
            .foregroundStyle(.white).background(.black), name: "page-small-reduced-motion", size: pageSize)
    }

    private var fixtureID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }

    private func fixture(scripts: [TeleprompterScript]) async -> TeleprompterModel {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 1_800_000_000), automaticallyAdvances: false)
        let model = TeleprompterModel(speech: MockTeleprompterSpeechService(),
            store: MockTeleprompterScriptStore(scripts: scripts), importer: MockTeleprompterDocumentService(),
            meetingContext: MockTeleprompterMeetingContextService(), calendar: MockCalendarService(),
            activities: ActivityCoordinator(clock: clock), clock: clock,
            uuids: SequenceUUIDGenerator(values: [fixtureID]))
        model.start()
        for _ in 0..<500 {
            if model.libraryLoaded { return model }
            await Task.yield()
        }
        XCTFail("Mock script library did not load")
        return model
    }

    private func renderPage(_ model: TeleprompterModel, name: String) async throws {
        let view = TeleprompterPage(model: model)
            .foregroundStyle(.white)
            .background(.black)
        let frames = try await render(view, name: name, size: pageSize)
        for identifier in ["notchium.teleprompter.edit", "notchium.teleprompter.script",
                           "notchium.teleprompter.mode", "notchium.teleprompter.play", "notchium.teleprompter.status",
                           "notchium.teleprompter.font.decrease", "notchium.teleprompter.font.increase"] {
            // SwiftUI can flatten accessibility groups differently between SDK releases.
            // When a native element is exposed, assert its complete hit area fits the page.
            if let frame = frames[identifier], !frame.isEmpty {
                XCTAssertTrue(CGRect(origin: .zero, size: pageSize).insetBy(dx: -1, dy: -1).contains(frame),
                              "\(identifier) clipped in \(name): \(frame)")
            }
        }
    }

    @discardableResult
    private func render(_ view: some View, name: String, size: CGSize) async throws -> [String: CGRect] {
        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
            .transaction { $0.disablesAnimations = true })
        host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(host.bounds.size, size)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(size.width))
        XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, Int(size.height))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1_000, "Fixture should contain rendered text and controls")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try png.write(to: destination.appendingPathComponent("\(name).png"))
        var frames: [String: CGRect] = [:]
        collectFrames(host, host: host, window: window, into: &frames, depth: 0)
        return frames
    }

    private func collectFrames(_ object: Any, host: NSView, window: NSWindow,
                               into frames: inout [String: CGRect], depth: Int) {
        guard depth < 30, let accessible = object as? any NSAccessibilityProtocol else { return }
        if let identifier = accessible.accessibilityIdentifier() {
            let screenFrame = accessible.accessibilityFrame()
            frames[identifier] = host.convert(window.convertFromScreen(screenFrame), from: nil)
        }
        for child in accessible.accessibilityChildren() ?? [] {
            collectFrames(child, host: host, window: window, into: &frames, depth: depth + 1)
        }
    }
}
