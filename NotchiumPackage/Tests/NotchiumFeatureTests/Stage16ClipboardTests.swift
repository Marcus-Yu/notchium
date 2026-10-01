import AppKit
import Foundation
import NotchiumCore
import XCTest
@testable import NotchiumClipboardFeature
@testable import NotchiumDynamicIsland
@testable import NotchiumServices
@testable import NotchiumShelfFeature
import SwiftUI

@MainActor
final class Stage16ClipboardTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTextLinkImageAndFileCapturesBecomeOneLineRows() throws {
        let (model, store, _) = make()
        model.receive(capture(.text("  \n  First useful line\nsecond line")))
        model.receive(capture(.url(URL(string: "https://www.example.com/docs/notch?x=1")!)))
        let image = try XCTUnwrap(ClipboardImageProcessing.content(from: pngData(width: 4000, height: 1000)))
        model.receive(capture(image))
        model.receive(capture(.files([URL(fileURLWithPath: "/Users/test/Report.pdf"), URL(fileURLWithPath: "/tmp/b.txt")])))

        XCTAssertEqual(model.items.map(\.kind), [.file, .image, .url, .text], "Newest first")
        XCTAssertEqual(model.items[3].preview, "First useful line")
        XCTAssertEqual(model.items[2].preview, "example.com/docs/notch")
        XCTAssertEqual(model.items[0].preview, "Report.pdf +1")
        guard case let .image(png, thumbnail, size) = image else { return XCTFail() }
        XCTAssertEqual(size, CGSize(width: 2048, height: 512), "Stored images are downsampled")
        XCTAssertLessThan(thumbnail.count, png.count)
        XCTAssertEqual(model.items[1].preview, "Image · 2048 × 512")
        XCTAssertNotNil(store.loadImage(id: model.items[1].id), "Image bytes live outside the in-memory list")
        XCTAssertNil(model.items[1].text)
    }

    func testCopyingTheSameThingAgainMovesItForward() {
        let (model, _, _) = make()
        model.receive(capture(.text("alpha")))
        model.receive(capture(.text("beta")))
        let alpha = model.items[1].id
        advance(60)
        model.receive(capture(.text("alpha")))
        XCTAssertEqual(model.items.map(\.text), ["alpha", "beta"])
        XCTAssertEqual(model.items[0].id, alpha, "Same item, moved, not duplicated")
        XCTAssertEqual(model.items[0].capturedAt, now)
    }

    func testClickToCopyWritesBackMovesForwardAndConfirmsInline() async {
        let (model, _, service) = make()
        model.receive(capture(.text("alpha")))
        model.receive(capture(.text("beta")))
        let alpha = model.items[1]
        model.copy(alpha)
        XCTAssertEqual(model.items.first?.id, alpha.id)
        XCTAssertEqual(model.lastCopiedID, alpha.id)
        await waitUntil { service.written.count == 1 }
        XCTAssertEqual(service.written, [.text("alpha")])
    }

    func testPinsSurviveCapacityAndClearAndAreBounded() {
        let (model, _, _) = make()
        model.historyLimit = 25
        model.receive(capture(.text("keep me")))
        model.togglePin(model.items[0])
        for index in 0..<40 { model.receive(capture(.text("item \(index)"))) }
        XCTAssertEqual(model.items.filter { !$0.isPinned }.count, 25, "History is bounded")
        XCTAssertEqual(model.items.first { $0.isPinned }?.text, "keep me", "Pinned items are never evicted")
        XCTAssertEqual(model.items.filter { !$0.isPinned }.first?.text, "item 39")
        XCTAssertEqual(model.visibleItems.first?.text, "keep me", "Pinned rows lead")

        for item in model.items.prefix(12) { model.togglePin(item) }
        XCTAssertEqual(model.items.count { $0.isPinned }, ClipboardModel.maximumPinned)
        XCTAssertFalse(model.canPin)

        model.delete(model.items.first { !$0.isPinned }!)
        model.clear()
        XCTAssertTrue(model.items.allSatisfy(\.isPinned))
        XCTAssertEqual(model.items.count, ClipboardModel.maximumPinned)
        model.clear(includingPinned: true)
        XCTAssertTrue(model.items.isEmpty)
    }

    func testRetentionRemovesOldUnpinnedItems() {
        let (model, _, _) = make()
        model.receive(capture(.text("old")))
        model.togglePin(model.items[0])
        model.receive(capture(.text("old unpinned")))
        advance(2 * 86_400)
        model.receive(capture(.text("new")))
        model.retention = .day
        XCTAssertEqual(model.items.map(\.text), ["new", "old"])
    }

    func testSearchFiltersByContent() {
        let (model, _, _) = make()
        model.receive(capture(.text("Meeting notes")))
        model.receive(capture(.url(URL(string: "https://apple.com/mac")!)))
        model.receive(capture(.files([URL(fileURLWithPath: "/tmp/Invoice.pdf")])))
        model.query = "invoice"
        XCTAssertEqual(model.visibleItems.map(\.kind), [.file])
        model.query = "APPLE"
        XCTAssertEqual(model.visibleItems.map(\.kind), [.url])
        model.query = ""
        XCTAssertEqual(model.visibleItems.count, 3)
    }

    func testPasswordManagerContentIsExcluded() async throws {
        XCTAssertTrue(ClipboardPrivacyPolicy.isExcluded(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
                                                        sourceBundleID: "com.apple.Safari"))
        XCTAssertTrue(ClipboardPrivacyPolicy.isExcluded(types: ["public.utf8-plain-text"], sourceBundleID: "com.1password.1password"))
        XCTAssertFalse(ClipboardPrivacyPolicy.isExcluded(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.TextEdit"))

        // A real, private pasteboard: concealed values are skipped, ordinary ones arrive.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("notchium.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let service = RealClipboardService(pasteboard: pasteboard)
        let stream = await service.captures()
        var received: [ClipboardCapture] = []
        let collector = Task { @MainActor in for await item in stream { received.append(item) } }
        defer { collector.cancel() }

        pasteboard.clearContents()
        pasteboard.setString("hunter2", forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        try await pump(seconds: 0.8)
        XCTAssertTrue(received.isEmpty, "Concealed content is never captured")

        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        try await pump(seconds: 0.8)
        XCTAssertEqual(received.map(\.content), [.text("hello")])

        await service.write(.text("from Notchium"))
        try await pump(seconds: 0.8)
        XCTAssertEqual(received.count, 1, "Notchium's own copy-back is not re-captured")
    }

    func testHistorySurvivesRestartAndImageFilesFollowTheList() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileClipboardStore(directory: directory)
        let first = ClipboardModel(service: MockClipboardService(), store: store, preferences: defaults(), now: { [base] in base })
        first.receive(capture(.text("persisted")))
        first.receive(capture(try XCTUnwrap(ClipboardImageProcessing.content(from: pngData(width: 64, height: 64)))))
        first.togglePin(first.items[1])

        let second = ClipboardModel(service: MockClipboardService(), store: FileClipboardStore(directory: directory),
                                    preferences: defaults(), now: { [base] in base })
        XCTAssertEqual(second.items.map(\.kind), [.image, .text])
        XCTAssertTrue(second.items[1].isPinned)
        let imageID = second.items[0].id
        XCTAssertNotNil(store.loadImage(id: imageID))
        second.delete(second.items[0])
        XCTAssertNil(store.loadImage(id: imageID), "Deleted images leave no file behind")
    }

    func testShelfAndClipboardToolbarsShareOneHeight() {
        func height<V: View>(_ view: V) -> CGFloat {
            let host = NSHostingView(rootView: view)
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.height
        }
        XCTAssertEqual(ShelfStyle.control, NotchToolbarMetrics.control, "Shelf is the reference and uses the shared metric")
        XCTAssertEqual(ShelfStyle.controlGap, NotchToolbarMetrics.controlGap)
        XCTAssertEqual(ShelfStyle.sectionGap, NotchToolbarMetrics.sectionGap)
        XCTAssertEqual(height(NotchToolbarButton(symbol: "trash", label: "Clear") {}), NotchToolbarMetrics.control)
        var query = "a long search that should never grow the row"
        let field = NotchToolbarSearchField(text: Binding(get: { query }, set: { query = $0 }), prompt: "Search")
        XCTAssertEqual(height(field), NotchToolbarMetrics.control, "Search never makes its row taller")
    }

    // MARK: Helpers

    private func make() -> (ClipboardModel, InMemoryClipboardStore, MockClipboardService) {
        let store = InMemoryClipboardStore()
        let service = MockClipboardService()
        let model = ClipboardModel(service: service, store: store, preferences: defaults(), now: { [unowned self] in now })
        return (model, store, service)
    }

    private func capture(_ content: ClipboardContent) -> ClipboardCapture {
        ClipboardCapture(content: content, capturedAt: now)
    }

    private func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

    private func defaults() -> UserDefaults {
        let name = "notchium.tests.clipboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// Lets the main run loop fire the service's change-count timer.
    private func pump(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    private func pngData(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        image.addRepresentation(rep)
        return rep.representation(using: .png, properties: [:])!
    }
}
