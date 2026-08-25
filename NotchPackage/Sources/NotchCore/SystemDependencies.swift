import Foundation

public protocol UUIDGenerating: Sendable {
    func next() async -> UUID
}

public struct SystemUUIDGenerator: UUIDGenerating {
    public init() {}

    public func next() async -> UUID {
        UUID()
    }
}

public actor SequenceUUIDGenerator: UUIDGenerating {
    private var remaining: [UUID]

    public init(values: [UUID]) {
        remaining = values
    }

    public func next() -> UUID {
        guard !remaining.isEmpty else {
            preconditionFailure("SequenceUUIDGenerator exhausted")
        }
        return remaining.removeFirst()
    }
}

public protocol FileSystemAccessing: Sendable {
    func temporaryDirectory() async -> URL
    func fileExists(at url: URL) async -> Bool
}

public struct SystemFileSystem: FileSystemAccessing {
    public init() {}

    public func temporaryDirectory() async -> URL {
        FileManager.default.temporaryDirectory
    }

    public func fileExists(at url: URL) async -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

public actor MockFileSystem: FileSystemAccessing {
    private let temporaryURL: URL
    private var existingURLs: Set<URL>

    public init(temporaryURL: URL, existingURLs: Set<URL> = []) {
        self.temporaryURL = temporaryURL
        self.existingURLs = existingURLs
    }

    public func temporaryDirectory() -> URL {
        temporaryURL
    }

    public func fileExists(at url: URL) -> Bool {
        existingURLs.contains(url)
    }

    public func setExists(_ exists: Bool, at url: URL) {
        if exists {
            existingURLs.insert(url)
        } else {
            existingURLs.remove(url)
        }
    }
}

public typealias DateProviding = AppClock
public typealias AppScheduling = AppClock
