import Darwin
import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
final class Stage27ShellStressTests: XCTestCase {
    func testThousandExpansionAndPageCyclesReleasePresentationOwnership() {
        weak var releasedModel: DynamicIslandPresentationModel?
        autoreleasepool {
            let model = DynamicIslandPresentationModel(clock: TestAppClock(now: .now, automaticallyAdvances: false))
            releasedModel = model
            for cycle in 0..<1_000 {
                model.present(.expanded, animated: false)
                for page in NotchPage.allCases { model.pageModel.selectedPage = page }
                let lease = "stress.\(cycle)"
                model.setAuxiliaryInteractionPresented(true, source: lease)
                model.setAuxiliaryInteractionPresented(false, source: lease)
                model.present(.collapsed, animated: false)
                XCTAssertEqual(model.visualState, .collapsed)
                XCTAssertFalse(model.isAuxiliaryInteractionPresented)
                XCTAssertFalse(model.pageModel.manualSelectionDuringExpansion)
                if (cycle + 1).isMultiple(of: 250) { recordMemory(cycles: cycle + 1) }
            }
            model.reset()
        }
        XCTAssertNil(releasedModel, "The shell and its observation graph must release after stress")
    }

    private func recordMemory(cycles: Int) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS { print("Stage27 model-only stress cycles=\(cycles) residentBytes=\(info.resident_size)") }
    }
}
