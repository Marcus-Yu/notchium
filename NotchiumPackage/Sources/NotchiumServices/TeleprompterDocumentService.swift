import AppKit
import Foundation

public enum TeleprompterDocumentFailure: Error, Equatable, Sendable, LocalizedError {
    case unsupportedFormat
    case unreadable
    case tooLarge
    case empty

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Choose a Word (.docx), rich text (.rtf), or text (.txt) file."
        case .unreadable: "The document could not be read. Try exporting it as a Word or text file."
        case .tooLarge: "This document is too large. Import a shorter script."
        case .empty: "No readable text was found in this document."
        }
    }
}

public protocol TeleprompterDocumentImporting: Sendable {
    /// Returns a local text snapshot. Never retains access to or edits the source document.
    func importDocument(at url: URL) async throws -> String
}

/// Decoding and file access remain on this actor, away from presentation work.
public actor RealTeleprompterDocumentService: TeleprompterDocumentImporting {
    public static let maximumFileBytes = 8 * 1_024 * 1_024
    public static let maximumTextBytes = 1_024 * 1_024

    public init() {}

    public func importDocument(at url: URL) async throws -> String {
        try Task.checkCancellation()
        guard url.isFileURL else { throw TeleprompterDocumentFailure.unreadable }
        let fileExtension = url.pathExtension.lowercased()
        guard ["txt", "rtf", "docx"].contains(fileExtension) else {
            throw TeleprompterDocumentFailure.unsupportedFormat
        }
        let scopedAccess = url.startAccessingSecurityScopedResource()
        defer { if scopedAccess { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { throw TeleprompterDocumentFailure.unreadable }
            guard (values.fileSize ?? 0) <= Self.maximumFileBytes else {
                throw TeleprompterDocumentFailure.tooLarge
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var bytes = Data()
            while let chunk = try handle.read(upToCount: min(65_536, Self.maximumFileBytes + 1 - bytes.count)),
                  !chunk.isEmpty {
                bytes.append(chunk)
                guard bytes.count <= Self.maximumFileBytes else { throw TeleprompterDocumentFailure.tooLarge }
                try Task.checkCancellation()
            }
            data = bytes
        } catch is CancellationError { throw CancellationError() }
        catch let failure as TeleprompterDocumentFailure { throw failure }
        catch { throw TeleprompterDocumentFailure.unreadable }

        let decoded: String
        do {
            switch fileExtension {
            case "txt":
                guard let text = String(data: data, encoding: .utf8)
                    ?? Self.decodeMarkedUnicode(data) else { throw TeleprompterDocumentFailure.unreadable }
                decoded = text
            case "rtf":
                decoded = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                 documentAttributes: nil).string
            default:
                try Self.validateWordArchive(data)
                decoded = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                                                 documentAttributes: nil).string
            }
        } catch let failure as TeleprompterDocumentFailure { throw failure }
        catch { throw TeleprompterDocumentFailure.unreadable }
        try Task.checkCancellation()
        let text = Self.normalize(decoded)
        guard text.utf8.count <= Self.maximumTextBytes else { throw TeleprompterDocumentFailure.tooLarge }
        guard !text.isEmpty else { throw TeleprompterDocumentFailure.empty }
        return text
    }

    /// Bound the archive's declared expansion before handing compressed input to AppKit.
    /// DOCX is a ZIP package; encrypted, split and ZIP64 archives are intentionally unsupported.
    private static func validateWordArchive(_ data: Data) throws {
        guard data.count >= 22 else { throw TeleprompterDocumentFailure.unreadable }
        func word(_ offset: Int) -> Int {
            Int(data[offset]) | Int(data[offset + 1]) << 8
        }
        func doubleWord(_ offset: Int) -> Int {
            word(offset) | word(offset + 2) << 16
        }
        let lowerBound = max(0, data.count - 65_557)
        guard let end = stride(from: data.count - 22, through: lowerBound, by: -1).first(where: {
            doubleWord($0) == 0x06054B50 && $0 + 22 + word($0 + 20) == data.count
        }), word(end + 4) == 0, word(end + 6) == 0,
              word(end + 8) == word(end + 10) else { throw TeleprompterDocumentFailure.unreadable }
        let entryCount = word(end + 10)
        let directorySize = doubleWord(end + 12)
        let directoryStart = doubleWord(end + 16)
        guard entryCount <= 2_048, directoryStart + directorySize <= end else {
            throw TeleprompterDocumentFailure.tooLarge
        }
        var cursor = directoryStart
        var expandedBytes = 0
        for _ in 0..<entryCount {
            guard cursor + 46 <= directoryStart + directorySize,
                  doubleWord(cursor) == 0x02014B50,
                  word(cursor + 8) & 1 == 0 else { throw TeleprompterDocumentFailure.unreadable }
            expandedBytes += doubleWord(cursor + 24)
            guard expandedBytes <= 32 * 1_024 * 1_024 else { throw TeleprompterDocumentFailure.tooLarge }
            cursor += 46 + word(cursor + 28) + word(cursor + 30) + word(cursor + 32)
            guard cursor <= directoryStart + directorySize else { throw TeleprompterDocumentFailure.unreadable }
        }
    }

    private static func decodeMarkedUnicode(_ data: Data) -> String? {
        // A BOM is required before interpreting non-UTF-8 text as UTF-16/32.
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) || data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return String(data: data, encoding: .utf32)
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        return nil
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct MockTeleprompterDocumentService: TeleprompterDocumentImporting {
    public let result: Result<String, TeleprompterDocumentFailure>

    public init(result: Result<String, TeleprompterDocumentFailure> = .success("A practice script.")) {
        self.result = result
    }

    public func importDocument(at url: URL) async throws -> String {
        try Task.checkCancellation()
        return try result.get()
    }
}
