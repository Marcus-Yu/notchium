import Foundation
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature

@MainActor
final class Stage27A1UIQualityTests: XCTestCase {
    func testMediaTimesFromOneHourIncludeHours() {
        XCTAssertEqual(MediaProgressView.time(0), "0:00")
        XCTAssertEqual(MediaProgressView.time(244), "4:04")
        XCTAssertEqual(MediaProgressView.time(3_599), "59:59")
        XCTAssertEqual(MediaProgressView.time(3_600), "1:00:00")
        XCTAssertEqual(MediaProgressView.time(7_265), "2:01:05", "A two-hour item must not read as 121:05")
        XCTAssertEqual(MediaProgressView.time(.nan), "0:00")
        XCTAssertEqual(MediaProgressView.time(-5), "0:00")
    }

    func testProgressScheduleTicksAtTenHertzOnlyWhilePlaying() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let playing = Array(MediaProgressSchedule(paused: false).entries(from: start, mode: .normal).prefix(4))
        for (index, date) in playing.enumerated() {
            XCTAssertEqual(date.timeIntervalSince(start), Double(index) * 0.1, accuracy: 1e-9)
        }
        let paused = Array(MediaProgressSchedule(paused: true).entries(from: start, mode: .normal).prefix(4))
        XCTAssertEqual(paused, [start], "A paused, hidden or seeking bar renders once and never wakes again")
    }

    func testRestoredCompactEntryIsNotIntroducedAgain() {
        let pods = UUID()
        let battery = UUID()
        var introduced = NotchCompactActivitySlot.introducing(pods, after: [])
        introduced = NotchCompactActivitySlot.introducing(battery, after: introduced)
        XCTAssertEqual(NotchCompactActivitySlot.introducing(pods, after: introduced), introduced,
                       "Returning after a battery alert, the AirPods entry is already introduced")
        XCTAssertTrue(introduced.contains(pods))

        let many = (0..<20).reduce(into: introduced) { ids, _ in
            ids = NotchCompactActivitySlot.introducing(UUID(), after: ids)
        }
        XCTAssertEqual(many.count, 8, "The memory stays bounded")
        XCTAssertFalse(many.contains(pods))
    }
}
