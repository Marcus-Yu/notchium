import Foundation

/// Everything the timer persists: its state and the local session records. Local only.
public struct PomodoroArchive: Codable, Equatable, Sendable {
    public var version = 1
    public var state = PomodoroState()
    public var records: [FocusSessionRecord] = []

    public init(state: PomodoroState = PomodoroState(), records: [FocusSessionRecord] = []) {
        self.state = state
        self.records = records
    }
}

public protocol PomodoroPersisting: AnyObject, Sendable {
    func load() -> PomodoroArchive
    func save(_ archive: PomodoroArchive)
    func flush()
}

public extension PomodoroPersisting { func flush() {} }

/// One small JSON file in Application Support, written atomically on each change.
public final class FilePomodoroStore: PomodoroPersisting, @unchecked Sendable {
    private let url: URL
    // Ordered atomic writes happen off MainActor with no deliberate batching delay.
    // Reads and graceful shutdown wait for preceding writes.
    private let queue = DispatchQueue(label: "notchium.pomodoro.store", qos: .utility)

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Notchium", isDirectory: true).appendingPathComponent("FocusTimer.json")
    }

    public func load() -> PomodoroArchive {
        queue.sync {
            guard let data = try? Data(contentsOf: url),
                  let archive = try? JSONDecoder.pomodoro.decode(PomodoroArchive.self, from: data) else { return PomodoroArchive() }
            return archive
        }
    }

    public func save(_ archive: PomodoroArchive) {
        queue.async { [url] in
            guard let data = try? JSONEncoder.pomodoro.encode(archive) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic])
        }
    }

    public func flush() { queue.sync {} }
}

public final class InMemoryPomodoroStore: PomodoroPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var archive: PomodoroArchive
    public private(set) var saveCount = 0

    public init(_ archive: PomodoroArchive = PomodoroArchive()) { self.archive = archive }

    public func load() -> PomodoroArchive {
        lock.lock(); defer { lock.unlock() }
        return archive
    }

    public func save(_ archive: PomodoroArchive) {
        lock.lock(); defer { lock.unlock() }
        self.archive = archive
        saveCount += 1
    }
}

private extension JSONEncoder {
    static var pomodoro: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

private extension JSONDecoder {
    static var pomodoro: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
