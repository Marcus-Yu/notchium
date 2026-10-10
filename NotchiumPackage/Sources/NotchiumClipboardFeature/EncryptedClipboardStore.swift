import Foundation

/// Local encrypted history. All disk work/key access stays on the Stage 22 ordered queue.
/// An unreadable store is never treated as empty writable history and never cleaned up.
public final class FileClipboardStore: ClipboardStoring, @unchecked Sendable {
    private let directory: URL
    private let keys: any ClipboardEncryptionKeyStoring
    private let queue = DispatchQueue(label: "notchium.clipboard.store", qos: .utility)
    private let stateLock = NSLock()
    private var storageState: ClipboardStorageState = .available
    private var stateChangeHandler: (@Sendable (ClipboardStorageState) -> Void)?
    private var disk: ClipboardDiskDirectory?
    private var key: Data?
    private var initialized = false
    private var imageIDs: Set<UUID>?
    private static let indexName = "history.clip"
    private static let indexLimit = 32_000_000
    private static let imageLimit = 20_000_000

    public init(directory: URL? = nil, keyStore: any ClipboardEncryptionKeyStoring = KeychainClipboardEncryptionKeyStore()) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchium/Clipboard", isDirectory: true)
        keys = keyStore
    }

    public var state: ClipboardStorageState { stateLock.withLock { storageState } }
    public var loadsAsynchronously: Bool { true }

    public func setStateChangeHandler(_ handler: (@Sendable (ClipboardStorageState) -> Void)?) {
        let current = stateLock.withLock {
            stateChangeHandler = handler
            return storageState
        }
        handler?(current)
    }

    public func loadItems() -> [ClipboardItem] {
        queue.sync { reload(allowAuthentication: false) }
    }

    public func loadItemsForRecovery(allowAuthentication: Bool) async -> [ClipboardItem] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: reload(allowAuthentication: allowAuthentication))
            }
        }
    }

    private func reload(allowAuthentication: Bool) -> [ClipboardItem] {
        // Only deliberate reads reset a failure; queued writes cannot reset errors.
        initialized = false
        key = nil
        imageIDs = nil
        do {
            let items = try prepare(allowAuthentication: allowAuthentication)
            setState(.available)
            return items
        } catch {
            record(error)
            return []
        }
    }

    public func saveItems(_ items: [ClipboardItem]) {
        queue.async { [self] in
            perform {
                let data = try JSONEncoder().encode(items)
                guard data.count <= Self.indexLimit else { throw ClipboardStorageFailure.invalidData }
                try disk!.write(ClipboardEncryption.seal(data, key: key!, identity: "history"), to: Self.indexName)
            }
        }
    }

    public func saveImage(_ png: Data, id: UUID) {
        queue.async { [self] in
            perform {
                guard png.count <= Self.imageLimit else { throw ClipboardStorageFailure.invalidData }
                try disk!.write(ClipboardEncryption.seal(png, key: key!, identity: id.uuidString), to: imageName(id))
                imageIDs?.insert(id)
            }
        }
    }

    public func loadImage(id: UUID) -> Data? {
        queue.sync {
            guard state == .available else { return nil }
            do {
                if !initialized { _ = try prepare() }
                guard let data = try disk!.read(imageName(id), maximumBytes: Self.imageLimit + 64) else { return nil }
                return try ClipboardEncryption.open(data, key: key!, identity: id.uuidString)
            } catch {
                record(error)
                return nil
            }
        }
    }

    public func removeImages(except ids: Set<UUID>) {
        queue.async { [self] in
            perform {
                if imageIDs == nil {
                    imageIDs = Set(try disk!.names().filter { $0.hasSuffix(".clip") }.compactMap {
                        UUID(uuidString: String($0.dropLast(5)))
                    })
                }
                for id in imageIDs!.subtracting(ids) {
                    try disk!.remove(imageName(id))
                    imageIDs?.remove(id)
                }
            }
        }
    }

    public func flush() { queue.sync {} }

    private func perform(_ operation: () throws -> Void) {
        guard state == .available else { return }
        do {
            if !initialized { _ = try prepare() }
            try operation()
        } catch { record(error) }
    }

    private func prepare(allowAuthentication: Bool = false) throws -> [ClipboardItem] {
        disk = try ClipboardDiskDirectory(url: directory)
        let names = try disk!.names()
        let hasEncryptedData = names.contains { $0.hasSuffix(".clip") }
        let storedKey = try keys.read(allowAuthentication: allowAuthentication)
        let candidateKey = try storedKey ?? (hasEncryptedData ? nil : keys.create(allowAuthentication: allowAuthentication))
        guard let loadedKey = candidateKey else {
            throw ClipboardStorageFailure.keyUnavailable
        }
        guard loadedKey.count == 32 else { throw ClipboardStorageFailure.invalidKey }
        key = loadedKey
        let items: [ClipboardItem]
        if let encrypted = try disk!.read(Self.indexName, maximumBytes: Self.indexLimit + 64) {
            let data = try ClipboardEncryption.open(encrypted, key: loadedKey, identity: "history")
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
            try validateEncryptedImages(in: items)
            // A crash after index commit may leave plaintext migration sources. Remove them
            // only after authenticating the committed encrypted index and all its image assets.
            if names.contains("history.json") { try finishMigration(items, names: names) }
        } else if let legacy = try disk!.read("history.json", maximumBytes: Self.indexLimit) {
            items = try JSONDecoder().decode([ClipboardItem].self, from: legacy)
            for item in items where item.kind == .image {
                guard let image = try disk!.read("\(item.id.uuidString).png", maximumBytes: Self.imageLimit) else {
                    throw ClipboardStorageFailure.invalidData
                }
                try disk!.write(ClipboardEncryption.seal(image, key: loadedKey, identity: item.id.uuidString),
                                to: imageName(item.id))
            }
            try disk!.write(ClipboardEncryption.seal(legacy, key: loadedKey, identity: "history"), to: Self.indexName)
            try finishMigration(items, names: names)
        } else {
            // Orphan ciphertext means a prior transaction may be incomplete. Without an
            // index, capture must not overwrite/clean up evidence of recoverable history.
            guard !hasEncryptedData else { throw ClipboardStorageFailure.invalidData }
            items = []
        }
        initialized = true
        return items
    }

    private func validateEncryptedImages(in items: [ClipboardItem]) throws {
        for item in items where item.kind == .image {
            guard let encrypted = try disk!.read(imageName(item.id), maximumBytes: Self.imageLimit + 64) else {
                throw ClipboardStorageFailure.invalidData
            }
            _ = try ClipboardEncryption.open(encrypted, key: key!, identity: item.id.uuidString)
        }
    }

    private func finishMigration(_ items: [ClipboardItem], names: [String]) throws {
        for item in items where item.kind == .image {
            guard let encrypted = try disk!.read(imageName(item.id), maximumBytes: Self.imageLimit + 64) else {
                throw ClipboardStorageFailure.invalidData
            }
            _ = try ClipboardEncryption.open(encrypted, key: key!, identity: item.id.uuidString)
        }
        // The encrypted index and every referenced image must survive a crash before the
        // plaintext recovery copies are removed.
        try disk!.synchronize()
        // Only UUID-named legacy payloads owned by this store are eligible for removal.
        for name in names where name.hasSuffix(".png") && UUID(uuidString: String(name.dropLast(4))) != nil {
            try disk!.remove(name)
        }
        try disk!.remove("history.json")
        try disk!.synchronize()
    }

    private func imageName(_ id: UUID) -> String { "\(id.uuidString).clip" }
    private func setState(_ value: ClipboardStorageState) {
        let handler = stateLock.withLock { () -> (@Sendable (ClipboardStorageState) -> Void)? in
            guard storageState != value else { return nil }
            storageState = value
            return stateChangeHandler
        }
        handler?(value)
    }
    private func record(_ error: any Error) {
        setState((error as? ClipboardStorageFailure)?.state ?? .unreadable)
        key = nil
        initialized = false
    }
}
