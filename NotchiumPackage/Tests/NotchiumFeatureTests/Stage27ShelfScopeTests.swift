import Foundation
import NotchiumServices
@testable import NotchiumShelfFeature
import XCTest

@MainActor
final class Stage27ShelfScopeTests: XCTestCase {
    func testRestoreAcquiresScopeBeforeCheckingExistenceAndKeepsTheBookmark() {
        let service = AccessGatedShelf()
        let shelf = ShelfModel(service: service)
        shelf.restore()
        XCTAssertEqual(shelf.items.map(\.url), [service.url])
        XCTAssertEqual(service.records.count, 1, "An unopened scope must not erase a valid saved bookmark")
        XCTAssertEqual(service.starts, 1)
        XCTAssertEqual(service.stops, 0)
        shelf.stopAccessingFiles()
        XCTAssertEqual(service.starts, service.stops)
    }

    func testRejectedMissingAndDuplicateReferencesReleaseTheirScopes() {
        for missing in [false, true] {
            let service = AccessGatedShelf()
            service.exists = !missing
            service.records.append(.init(id: UUID(), reference: Data(), addedAt: Date()))
            let shelf = ShelfModel(service: service)
            shelf.restore()
            XCTAssertEqual(shelf.items.count, missing ? 0 : 1)
            XCTAssertEqual(service.starts, 2)
            XCTAssertEqual(service.stops, missing ? 2 : 1)
            shelf.stopAccessingFiles()
            XCTAssertEqual(service.starts, service.stops)
        }
    }

    func testMovedBookmarkAcquiresItsNewURLBeforeReleasingTheOldScope() {
        let service = AccessGatedShelf()
        let shelf = ShelfModel(service: service)
        shelf.restore()
        service.url = URL(fileURLWithPath: "/private/tmp/notchium-stage27-moved-fixture")
        shelf.refreshAvailability()
        XCTAssertEqual(shelf.items.map(\.url), [service.url])
        XCTAssertEqual(shelf.items.first?.isAvailable, true)
        XCTAssertEqual(service.starts, 2)
        XCTAssertEqual(service.stops, 1)
        shelf.stopAccessingFiles()
        XCTAssertEqual(service.starts, service.stops)
    }
}

@MainActor
private final class AccessGatedShelf: ShelfService {
    var url = URL(fileURLWithPath: "/private/tmp/notchium-stage27-scoped-fixture")
    var records = [ShelfRecord(id: UUID(), reference: Data(), addedAt: Date())]
    var starts = 0
    var stops = 0
    var exists = true
    private var active: [URL: Int] = [:]
    func loadRecords() -> [ShelfRecord] { records }
    func saveRecords(_ records: [ShelfRecord]) { self.records = records }
    func reference(for url: URL) -> Data? { Data() }
    func resolve(_ reference: Data) -> ResolvedShelfReference? { .init(url: url, isStale: false) }
    func fileExists(_ url: URL) -> Bool { exists && url == self.url && active[url, default: 0] > 0 }
    func startAccessing(_ url: URL) -> Bool { starts += 1; active[url, default: 0] += 1; return true }
    func stopAccessing(_ url: URL) { stops += 1; active[url, default: 0] -= 1 }
}
