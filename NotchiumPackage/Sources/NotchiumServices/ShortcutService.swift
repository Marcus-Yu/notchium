import Foundation
import Synchronization
import NotchiumCore

public enum QuickActionFailure: LocalizedError, Equatable {
    case unavailable, invalidURL, shortcutMissing, shortcutFailed, discoveryFailed, disabled
    public var errorDescription: String? {
        switch self {
        case .unavailable: "This item is unavailable. Edit the action to select it again."
        case .invalidURL: "Enter a valid http or https website address."
        case .shortcutMissing: "This shortcut is missing or ambiguous. Refresh and select it again."
        case .shortcutFailed: "The shortcut did not complete. Check it in Shortcuts and try again."
        case .discoveryFailed: "Couldn’t load shortcuts. Open Shortcuts, then refresh."
        case .disabled: "This action is disabled. Enable it in Settings."
        }
    }
}

public protocol ShortcutService: Sendable {
    func list() async throws -> [ExistingShortcut]
    func run(_ shortcut: ExistingShortcut) async throws
}

/// Only Apple's fixed executable and argument arrays are used. No shell or scripts.
public struct AppleShortcutService: ShortcutService {
    public init() {}
    public func list() async throws -> [ExistingShortcut] {
        let output = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await execute(["list", "--show-identifiers"], collectingOutput: true) }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw QuickActionFailure.discoveryFailed
            }
            defer { group.cancelAll() }
            return try await group.next() ?? ""
        }
        return try Self.parseList(output)
    }
    public func run(_ shortcut: ExistingShortcut) async throws {
        // Revalidate immediately before execution; never fuzzy-match another shortcut.
        let names = try await list()
        guard names.filter({ $0 == shortcut }).count == 1 else { throw QuickActionFailure.shortcutMissing }
        _ = try await execute(["run", "--", shortcut.id.uuidString], collectingOutput: false)
    }
    public static func parseList(_ output: String) throws -> [ExistingShortcut] {
        try output.split(separator: "\n").map { line in
            guard line.hasSuffix(")"), let separator = line.range(of: " (", options: .backwards),
                  let id = UUID(uuidString: String(line[separator.upperBound...].dropLast())),
                  !line[..<separator.lowerBound].isEmpty else { throw QuickActionFailure.discoveryFailed }
            return ExistingShortcut(id: id, name: String(line[..<separator.lowerBound]))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private func execute(_ arguments: [String], collectingOutput: Bool) async throws -> String {
        let lifetime = ShortcutProcessLifetime()
        let process = lifetime.process
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        // A file avoids pipe backpressure for large collections. Shortcut output is discarded.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
            attributes: [.posixPermissions: 0o600]) else { throw QuickActionFailure.discoveryFailed }
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close(); try? FileManager.default.removeItem(at: url) }
        process.standardOutput = collectingOutput ? output : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let status: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { completed in
                    continuation.resume(returning: completed.terminationStatus)
                }
                do { try lifetime.launch() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            lifetime.cancel()
        }
        try Task.checkCancellation()
        guard status == 0 else {
            throw collectingOutput ? QuickActionFailure.discoveryFailed : QuickActionFailure.shortcutFailed
        }
        return collectingOutput ? String(decoding: try Data(contentsOf: url), as: UTF8.self) : ""
    }
}

public actor MockShortcutService: ShortcutService {
    public var shortcuts: [ExistingShortcut]
    public private(set) var executions: [ExistingShortcut] = []
    public init(shortcuts: [ExistingShortcut] = []) { self.shortcuts = shortcuts }
    public func list() -> [ExistingShortcut] { shortcuts }
    public func run(_ shortcut: ExistingShortcut) throws {
        guard shortcuts.filter({ $0 == shortcut }).count == 1 else { throw QuickActionFailure.shortcutMissing }
        executions.append(shortcut)
    }
    public func setShortcuts(_ shortcuts: [ExistingShortcut]) { self.shortcuts = shortcuts }
}

/// Launch and cancellation share a lock so cancellation before launch cannot orphan a process.
private final class ShortcutProcessLifetime: Sendable {
    let process = Process()
    private let cancelled = Mutex(false)
    func launch() throws {
        try cancelled.withLock { value in
            guard !value else { throw CancellationError() }
            try process.run()
        }
    }
    func cancel() {
        cancelled.withLock { value in
            value = true
            if process.isRunning { process.terminate() }
        }
    }
}
