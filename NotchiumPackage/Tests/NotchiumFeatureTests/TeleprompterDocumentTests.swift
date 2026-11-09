import Foundation
import NotchiumCore
import NotchiumPersistence
import NotchiumServices
import XCTest

@MainActor
final class TeleprompterDocumentTests: XCTestCase {
    func testTextImportNormalizesParagraphsWithoutRetainingTheSource() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "script.txt")
        try "\u{FEFF}Opening\r\nSecond\rThird\u{2028}Fourth\u{FFFC}\n".write(to: source, atomically: true, encoding: .utf8)
        let imported = try await RealTeleprompterDocumentService().importDocument(at: source)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(imported, "Opening\nSecond\nThird\nFourth")
    }

    func testWordImportExtractsBodyAndTableText() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "script.docx")
        try Self.wordFixture.write(to: source)
        let imported = try await RealTeleprompterDocumentService().importDocument(at: source)
        XCTAssertTrue(imported.contains("Opening paragraph."))
        XCTAssertTrue(imported.contains("First cell"))
        XCTAssertTrue(imported.contains("Second cell"))
        XCTAssertTrue(imported.hasSuffix("Closing paragraph."))
    }

    func testRichTextImport() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "script.rtf")
        try Data(#"{\rtf1\ansi Opening \b important\b0 \par Second paragraph.}"#.utf8).write(to: source)
        let imported = try await RealTeleprompterDocumentService().importDocument(at: source)
        XCTAssertTrue(imported.contains("Opening important"))
        XCTAssertTrue(imported.contains("Second paragraph."))
        XCTAssertFalse(imported.contains("\\b"))
    }

    func testImportRejectsUnsupportedMalformedAndEmptyDocuments() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let importer = RealTeleprompterDocumentService()
        for (name, contents, expected) in [
            ("script.pdf", Data("not a PDF".utf8), TeleprompterDocumentFailure.unsupportedFormat),
            ("script.docx", Data("not a Word package".utf8), .unreadable),
            ("script.txt", Data(" \n\t ".utf8), .empty),
            ("binary.txt", Data([0xC3, 0x28]), .unreadable)
        ] {
            let source = directory.appending(path: name)
            try contents.write(to: source)
            do {
                _ = try await importer.importDocument(at: source)
                XCTFail("Unexpectedly imported \(name)")
            } catch let failure as TeleprompterDocumentFailure { XCTAssertEqual(failure, expected) }
        }
    }

    func testImportRejectsOversizedInputBeforeDecoding() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "large.txt")
        try Data(repeating: 0x61, count: RealTeleprompterDocumentService.maximumFileBytes + 1).write(to: source)
        do {
            _ = try await RealTeleprompterDocumentService().importDocument(at: source)
            XCTFail("Oversized document should be rejected")
        } catch let failure as TeleprompterDocumentFailure { XCTAssertEqual(failure, .tooLarge) }
    }

    func testWordImportRejectsExcessiveDeclaredExpansion() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "expanded.docx")
        var archive = Self.wordFixture
        let centralSignature = Data([0x50, 0x4B, 0x01, 0x02])
        let centralEntry = try XCTUnwrap(archive.range(of: centralSignature)?.lowerBound)
        // A small compressed package claims a >32MB first entry. Reject before native decoding.
        archive.replaceSubrange((centralEntry + 24)..<(centralEntry + 28), with: [0x00, 0x00, 0x00, 0x04])
        try archive.write(to: source)
        do {
            _ = try await RealTeleprompterDocumentService().importDocument(at: source)
            XCTFail("Excessive ZIP expansion should be rejected")
        } catch let failure as TeleprompterDocumentFailure { XCTAssertEqual(failure, .tooLarge) }
    }

    func testLibraryRoundTripAndDeletionPreserveUnicodeAndIdentity() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appending(path: "library/scripts.json")
        let store = RealTeleprompterScriptStore(location: location)
        let missing = try await store.load()
        XCTAssertEqual(missing, [])
        let first = TeleprompterScript(id: UUID(), title: "Résumé", text: "Hello, 世界.\nSecond paragraph.")
        let second = TeleprompterScript(id: UUID(), title: "Remove me", text: "Private removed script.")
        try await store.save([first, second])
        let loaded = try await RealTeleprompterScriptStore(location: location).load()
        XCTAssertEqual(loaded, [first, second])
        try await store.save([first])
        let afterDeletion = try await store.load()
        XCTAssertEqual(afterDeletion, [first])
        XCTAssertFalse(try String(contentsOf: location, encoding: .utf8).contains(second.text))
        let permissions = try FileManager.default.attributesOfItem(atPath: location.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testUnreadableAndNewerLibrariesRemainUnchanged() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appending(path: "scripts.json")
        for (data, expected) in [
            (Data("broken JSON".utf8), TeleprompterScriptStoreFailure.unreadable),
            (Data(#"{"version":2,"scripts":[]}"#.utf8), .unsupportedVersion)
        ] {
            try data.write(to: location)
            do {
                _ = try await RealTeleprompterScriptStore(location: location).load()
                XCTFail("Invalid library should not be silently reset")
            } catch let failure as TeleprompterScriptStoreFailure { XCTAssertEqual(failure, expected) }
            XCTAssertEqual(try Data(contentsOf: location), data)
        }
    }

    func testOversizedScriptDoesNotReplaceSavedLibrary() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appending(path: "scripts.json")
        let store = RealTeleprompterScriptStore(location: location)
        let original = TeleprompterScript(id: UUID(), title: "Original", text: "Keep this script.")
        try await store.save([original])
        let oversized = TeleprompterScript(id: UUID(), title: "Too long",
            text: String(repeating: "x", count: RealTeleprompterScriptStore.maximumScriptBytes + 1))
        do {
            try await store.save([oversized])
            XCTFail("Oversized script should not replace saved bytes")
        } catch let failure as TeleprompterScriptStoreFailure { XCTAssertEqual(failure, .tooLarge) }
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [original])
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "notchium-document-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Minimal actual DOCX package: content types, package relationship and Word body/table XML.
    private static let wordFixture = Data(base64Encoded: """
    UEsDBBQAAAAIAAAAIVz3VP4j2QAAAGQBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbJWQu1LDMBBFf0WjlrHWUDAMYzsFjxIowgfsyGtbg16jVUL4e9YJSZGOUrpn75G22xyCV3sq7FLs9a1ptaJo0+ji3OvP7WvzoDdDt/3JxErQyL1eas2PAGwXCsgmZYqSTKkErHIsM2S0XzgT3LXtPdgUK8Xa1LVDD90zTbjzVb0c5PqkLeRZq6cTuLp6jTl7Z7FKDvs4XlmaP4ORySPDi8t8I4CGoXuX/xQ3kvrAUt8wSB18pzLCmOwuiMKs4L98aZqcpcv82pZLssQsiwreXJKALp7fAce1Db9QSwMEFAAAAAgAAAAhXDZX3tyiAAAAGAEAAAsAAABfcmVscy8ucmVsc43POw7CMAwG4KtE3qkLA0KoaReE1BWVA0SJm0Y0DyXhdXsyMFDEwGj792e56R52ZjeKyXjHYV3VwMhJr4zTHM7DcbWDrm1ONItcEmkyIbGy4hKHKeewR0xyIitS5QO5Mhl9tCKXMmoMQl6EJtzU9RbjpwFLk/WKQ+zVGtjwDPSP7cfRSDp4ebXk8o8TX4kii6gpc7j7qFC921VhAdsGFy+2L1BLAwQUAAAACAAAACFcYBWTesgAAACKAQAAEQAAAHdvcmQvZG9jdW1lbnQueG1shZDBjsIgEIZfhXC3Uz2YTdPWg4lXD7oPgIBtE2DIgHb37RfadDW7Jl7+Ccz/f8xQ776sYXdNYUDX8HVRcqadRDW4ruGf58Pqg+/aeqwUypvVLrLkd6EaG97H6CuAIHttRSjQa5d6VyQrYjpSByOS8oRSh5Bw1sCmLLdgxeB4Rl5Qfefqs1CW2B4TJXmZFyQ6Er4vasj3WWnSyR0vZipzSv6lHAYKkUltzIs0LIn/uZOW6NSbIMzvwu8Uz4S9wfB2flh2h8e/tj9QSwECFAMUAAAACAAAACFc91T+I9kAAABkAQAAEwAAAAAAAAAAAAAAgAEAAAAAW0NvbnRlbnRfVHlwZXNdLnhtbFBLAQIUAxQAAAAIAAAAIVw2V97cogAAABgBAAALAAAAAAAAAAAAAACAAQoBAABfcmVscy8ucmVsc1BLAQIUAxQAAAAIAAAAIVxgFZN6yAAAAIoBAAARAAAAAAAAAAAAAACAAdUBAAB3b3JkL2RvY3VtZW50LnhtbFBLBQYAAAAAAwADALkAAADMAgAAAAA=
    """.filter { !$0.isWhitespace })!
}
