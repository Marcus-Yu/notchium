import Darwin
import Foundation

/// A descriptor anchors all reads/writes/deletions to the opened app-owned directory.
/// No path component or payload may be a symlink; replacing a path cannot redirect cleanup.
final class ClipboardDiskDirectory {
    private let descriptor: Int32

    init(url: URL) throws {
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw ClipboardStorageFailure.unsafeFile }
        do {
            guard url.isFileURL, url.path.hasPrefix("/") else { throw ClipboardStorageFailure.unsafeFile }
            for component in url.pathComponents where component != "/" {
                guard component != ".", component != ".." else { throw ClipboardStorageFailure.unsafeFile }
                var next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0 && errno == ENOENT {
                    guard mkdirat(current, component, 0o700) == 0 || errno == EEXIST else {
                        throw ClipboardStorageFailure.unsafeFile
                    }
                    next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw ClipboardStorageFailure.unsafeFile }
                Darwin.close(current)
                current = next
            }
            guard fchmod(current, 0o700) == 0 else { throw ClipboardStorageFailure.unsafeFile }
            descriptor = current
        } catch {
            Darwin.close(current)
            throw error
        }
    }

    deinit { Darwin.close(descriptor) }

    func names() throws -> [String] {
        guard let directory = fdopendir(dup(descriptor)) else { throw ClipboardStorageFailure.unsafeFile }
        defer { closedir(directory) }
        rewinddir(directory)
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }

    func read(_ name: String, maximumBytes: Int) throws -> Data? {
        try validateName(name)
        let file = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if file < 0 && errno == ENOENT { return nil }
        guard file >= 0 else { throw ClipboardStorageFailure.unsafeFile }
        defer { Darwin.close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_nlink == 1, info.st_size >= 0, info.st_size <= maximumBytes else {
            throw ClipboardStorageFailure.unsafeFile
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw ClipboardStorageFailure.unsafeFile }
            if count == 0 { return data }
            guard data.count + count <= maximumBytes else { throw ClipboardStorageFailure.invalidData }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    func write(_ data: Data, to name: String) throws {
        try validateName(name)
        try validateExisting(name)
        let temporary = ".pending-\(UUID().uuidString)"
        let file = openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw ClipboardStorageFailure.unsafeFile }
        defer { Darwin.close(file); unlinkat(descriptor, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(file, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ClipboardStorageFailure.unsafeFile }
                offset += count
            }
        }
        guard fsync(file) == 0, renameat(descriptor, temporary, descriptor, name) == 0 else {
            throw ClipboardStorageFailure.unsafeFile
        }
        try synchronize()
    }

    func remove(_ name: String) throws {
        try validateName(name)
        try validateExisting(name)
        guard unlinkat(descriptor, name, 0) == 0 || errno == ENOENT else {
            throw ClipboardStorageFailure.unsafeFile
        }
    }

    /// Makes directory-entry changes durable after atomic rename or migration cleanup.
    func synchronize() throws {
        while fsync(descriptor) != 0 {
            if errno == EINTR { continue }
            throw ClipboardStorageFailure.unsafeFile
        }
    }

    private func validateExisting(_ name: String) throws {
        var info = stat()
        let result = fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW)
        if result < 0 && errno == ENOENT { return }
        guard result == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1 else {
            throw ClipboardStorageFailure.unsafeFile
        }
    }

    private func validateName(_ name: String) throws {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
            throw ClipboardStorageFailure.unsafeFile
        }
    }
}
