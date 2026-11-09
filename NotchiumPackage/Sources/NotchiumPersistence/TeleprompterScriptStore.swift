import Foundation
import NotchiumCore

public enum TeleprompterScriptStoreFailure: Error, Equatable, Sendable, LocalizedError {
    case unreadable
    case unwritable
    case unsupportedVersion
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .unreadable: "Saved scripts could not be read. The original library has been preserved."
        case .unwritable: "Scripts could not be saved on this Mac."
        case .unsupportedVersion: "This script library was saved by a newer version of Notchium."
        case .tooLarge: "The script library is full. Shorten a script or remove one before saving."
        }
    }
}

public protocol TeleprompterScriptStoring: Sendable {
    func load() async throws -> [TeleprompterScript]
    func save(_ scripts: [TeleprompterScript]) async throws
}

/// One atomic, versioned local library. Source files, microphone audio and recognized speech
/// never enter this store. A failed load is not repaired by replacing the original bytes.
public actor RealTeleprompterScriptStore: TeleprompterScriptStoring {
    public static let maximumScripts = 100
    public static let maximumScriptBytes = 1_024 * 1_024
    public static let maximumLibraryBytes = 16 * 1_024 * 1_024

    private struct Library: Codable {
        var version: Int
        var scripts: [TeleprompterScript]
    }

    private let location: URL
    private let fileManager: FileManager

    public init(location: URL? = nil) {
        let manager = FileManager()
        fileManager = manager
        self.location = location ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "com.marcusyu.notchium/Teleprompter/scripts-v1.json")
    }

    public func load() async throws -> [TeleprompterScript] {
        try Task.checkCancellation()
        guard fileManager.fileExists(atPath: location.path) else { return [] }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: location.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.intValue <= Self.maximumLibraryBytes else { throw TeleprompterScriptStoreFailure.tooLarge }
            let data = try Data(contentsOf: location)
            guard data.count <= Self.maximumLibraryBytes else { throw TeleprompterScriptStoreFailure.tooLarge }
            let library = try JSONDecoder().decode(Library.self, from: data)
            guard library.version == 1 else { throw TeleprompterScriptStoreFailure.unsupportedVersion }
            try Self.validate(library.scripts)
            return library.scripts
        } catch let failure as TeleprompterScriptStoreFailure { throw failure }
        catch { throw TeleprompterScriptStoreFailure.unreadable }
    }

    public func save(_ scripts: [TeleprompterScript]) async throws {
        try Task.checkCancellation()
        try Self.validate(scripts)
        do {
            let data = try JSONEncoder().encode(Library(version: 1, scripts: scripts))
            guard data.count <= Self.maximumLibraryBytes else { throw TeleprompterScriptStoreFailure.tooLarge }
            try fileManager.createDirectory(at: location.deletingLastPathComponent(),
                                            withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            try data.write(to: location, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        } catch let failure as TeleprompterScriptStoreFailure { throw failure }
        catch { throw TeleprompterScriptStoreFailure.unwritable }
    }

    private static func validate(_ scripts: [TeleprompterScript]) throws {
        guard scripts.count <= maximumScripts,
              Set(scripts.map(\.id)).count == scripts.count,
              scripts.allSatisfy({ $0.text.utf8.count <= maximumScriptBytes && $0.title.utf8.count <= 4_096 }) else {
            throw TeleprompterScriptStoreFailure.tooLarge
        }
    }
}

public actor MockTeleprompterScriptStore: TeleprompterScriptStoring {
    public var scripts: [TeleprompterScript]
    public var failure: TeleprompterScriptStoreFailure?

    public init(scripts: [TeleprompterScript] = [], failure: TeleprompterScriptStoreFailure? = nil) {
        self.scripts = scripts
        self.failure = failure
    }

    public func load() async throws -> [TeleprompterScript] {
        if let failure { throw failure }
        return scripts
    }

    public func save(_ scripts: [TeleprompterScript]) async throws {
        if let failure { throw failure }
        self.scripts = scripts
    }
}
