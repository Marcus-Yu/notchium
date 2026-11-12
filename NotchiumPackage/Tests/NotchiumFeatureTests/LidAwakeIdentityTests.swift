import Foundation
import NotchiumServices
import Security
import XCTest

/// The free helper is shared by every macOS account and launched from whichever copy of the app
/// registered it, so its client check must accept every copy of one build and nothing else.
final class LidAwakeIdentityTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testBuildRequirementAcceptsEveryCopyOfTheBuildAndRejectsOtherBinaries() throws {
        // Two installs of one build (say, ~/Applications in one account and /Applications in
        // another), and a different binary that reuses the app's identifier.
        let build = try compile("#include <unistd.h>\nint main(void) { sleep(30); return 0; }\n", into: "main-account")
        let otherCopy = try copy(build, to: "other-account")
        let impostor = try compile("int main(void) { return 1; }\n", into: "impostor")

        let hash = try XCTUnwrap(LidAwakeIdentity.cdhash(of: build))
        XCTAssertEqual(LidAwakeIdentity.cdhash(of: otherCopy), hash, "Copies of one build share a hash")
        XCTAssertNotEqual(LidAwakeIdentity.cdhash(of: impostor), hash)
        XCTAssertNil(LidAwakeIdentity.cdhash(of: folder.appendingPathComponent("missing")))

        let requirement = LidAwakeIdentity.appBuildRequirement(cdhash: hash)
        XCTAssertEqual(requirement, "identifier \"com.marcusyu.notchium\" and cdhash H\""
            + hash.map { String(format: "%02x", $0) }.joined() + "\"")
        XCTAssertTrue(try satisfies(otherCopy, requirement), "Another location's copy is accepted")
        XCTAssertFalse(try satisfies(impostor, requirement), "Reusing the identifier is not enough")
        XCTAssertTrue(try satisfies(impostor, "identifier \"\(LidAwakeIdentity.app)\""),
                      "Control: an identifier-only rule cannot tell them apart")

        // The helper checks the live client process, as XPC does for every message.
        let process = Process()
        process.executableURL = otherCopy
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }
        XCTAssertTrue(try liveProcess(process.processIdentifier, satisfies: requirement))
    }

    /// A single-architecture, ad-hoc signed executable, like the shipped app (`ARCHS=arm64`).
    /// Multi-architecture system binaries are unsuitable: macOS may run a different slice than
    /// the one whose hash is read from disk.
    private func compile(_ source: String, into name: String) throws -> URL {
        let directory = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("main.c")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let executable = directory.appendingPathComponent("Notchium")
        try run("/usr/bin/xcrun", ["clang", file.path, "-o", executable.path])
        try run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", LidAwakeIdentity.app, executable.path])
        return executable
    }

    private func copy(_ executable: URL, to name: String) throws -> URL {
        let directory = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(executable.lastPathComponent)
        try FileManager.default.copyItem(at: executable, to: destination)
        return destination
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(tool) \(arguments.joined(separator: " "))")
    }

    private func requirement(_ text: String) throws -> SecRequirement {
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
        return try XCTUnwrap(requirement)
    }

    private func satisfies(_ url: URL, _ text: String) throws -> Bool {
        var code: SecStaticCode?
        XCTAssertEqual(SecStaticCodeCreateWithPath(url as CFURL, [], &code), errSecSuccess)
        return SecStaticCodeCheckValidity(try XCTUnwrap(code), [], try requirement(text)) == errSecSuccess
    }

    private func liveProcess(_ pid: pid_t, satisfies text: String) throws -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        XCTAssertEqual(SecCodeCopyGuestWithAttributes(nil, attributes, [], &code), errSecSuccess)
        return SecCodeCheckValidity(try XCTUnwrap(code), [], try requirement(text)) == errSecSuccess
    }
}
