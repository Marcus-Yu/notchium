import Foundation
import XCTest
@testable import NotchiumClipboardFeature
@testable import NotchiumServices

@MainActor
final class Stage23ClipboardOptInTests: XCTestCase {
    func testCaptureChoicePersistsAndDisabledModelKeepsHistoryUsable() {
        let name = "notchium.stage23.clipboard.optin.\(UUID())"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let store = InMemoryClipboardStore()
        let service = MockClipboardService()

        let model = ClipboardModel(service: service, store: store, preferences: preferences,
                                   captureEnabledByDefault: false)
        XCTAssertFalse(model.captureEnabled)
        model.receive(ClipboardCapture(content: .text("while disabled"), capturedAt: Date()))
        XCTAssertTrue(model.items.isEmpty)

        model.captureEnabled = true
        model.receive(ClipboardCapture(content: .text("while enabled"), capturedAt: Date()))
        XCTAssertEqual(model.items.map(\.text), ["while enabled"])

        let reopened = ClipboardModel(service: service, store: store, preferences: preferences,
                                      captureEnabledByDefault: false)
        XCTAssertTrue(reopened.captureEnabled)
        XCTAssertEqual(reopened.items, model.items)
        reopened.captureEnabled = false
        let disabledAgain = ClipboardModel(service: service, store: store, preferences: preferences,
                                           captureEnabledByDefault: false)
        XCTAssertFalse(disabledAgain.captureEnabled)
        XCTAssertEqual(disabledAgain.items, model.items)
    }

    func testExistingFixturesRemainCaptureEnabledByDefault() {
        let name = "notchium.stage23.clipboard.default.\(UUID())"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let model = ClipboardModel(service: MockClipboardService(), store: InMemoryClipboardStore(),
                                   preferences: preferences)
        XCTAssertTrue(model.captureEnabled)
    }
}
