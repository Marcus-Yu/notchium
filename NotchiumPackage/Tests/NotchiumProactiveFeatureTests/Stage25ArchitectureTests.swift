import Foundation
import XCTest

final class Stage25ArchitectureTests: XCTestCase {
    private var package: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testFoundationHasOnlyValueTypesAndNoSideEffectPaths() throws {
        let coreNames = ["SuggestionIdentity.swift", "SuggestionCandidate.swift", "SuggestionFeedback.swift",
                         "SuggestionEligibility.swift", "ProactiveTime.swift"]
        let core = package.appendingPathComponent("Sources/NotchiumCore")
        let feature = package.appendingPathComponent("Sources/NotchiumProactiveFeature")
        let files = coreNames.map { core.appendingPathComponent($0) }
            + (try FileManager.default.contentsOfDirectory(at: feature, includingPropertiesForKeys: nil))
                .filter { $0.pathExtension == "swift" }
        let forbidden = [#"\b(class|actor|protocol)\s+"#, #"@unchecked"#, #"\bTask\s*[({]"#,
                         #"\b(Timer|NotificationCenter|NSWorkspace|FileManager|Process|URLSession|UserDefaults)\b"#,
                         #"\b(Date|UUID)\(\)"#, #"Date\.now"#, #"\.sleep\("#,
                         #"\b(URL|String|Any)\s*[?\]:,)]"#]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for pattern in forbidden {
                XCTAssertNil(source.range(of: pattern, options: .regularExpression), "\(file.lastPathComponent): \(pattern)")
            }
            for line in source.split(separator: "\n") where line.hasPrefix("import ") {
                XCTAssertTrue(["import Foundation", "import NotchiumCore"].contains(String(line)), file.lastPathComponent)
            }
        }
    }

    func testPackageTargetIsCoreOnlyAndNotAttachedToProductionComposition() throws {
        let manifest = try String(contentsOf: package.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertNotNil(manifest.range(of: #"name: "NotchiumProactiveFeature",\s*dependencies: \["NotchiumCore"\]"#,
                                       options: .regularExpression))
        let production = package.appendingPathComponent("Sources/NotchiumFeature")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: production, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("NotchiumProactiveFeature"), file.lastPathComponent)
            XCTAssertFalse(source.contains("SuggestionFeedbackState"), file.lastPathComponent)
            XCTAssertFalse(source.contains("SuggestionInterruptionPolicy"), file.lastPathComponent)
        }
        let rootTarget = try XCTUnwrap(manifest.range(of: "name: \"NotchiumFeature\","))
        let remainder = manifest[rootTarget.upperBound...]
        let end = try XCTUnwrap(remainder.range(of: ".target("))
        XCTAssertFalse(remainder[..<end.lowerBound].contains("NotchiumProactiveFeature"))
    }
}
