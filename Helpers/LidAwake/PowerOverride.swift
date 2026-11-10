import Foundation
import IOKit.ps

/// Accessed only by the helper's serial queue. Journal is root-owned and written
/// before changing the persistent system setting, so restart can recover it.
final class PowerOverride {
    private let journal: URL
    private var lock: Int32?
    private let runCommand: ([String]) throws -> String
    private let conditions: () -> Bool
    private(set) var ownsOverride = false

    init(
        journal: URL = URL(fileURLWithPath: "/var/db/com.marcusyu.notchium.lid-awake"),
        runCommand: @escaping ([String]) throws -> String = PowerOverride.runPMSet,
        conditions: @escaping () -> Bool = PowerOverride.checkConditions
    ) {
        self.journal = journal
        self.runCommand = runCommand
        self.conditions = conditions
    }

    deinit { unlock() }

    func recover() throws {
        try lockJournal()
        defer { if !ownsOverride { unlock() } }
        try restoreJournaledOverride()
    }

    func acquire() throws {
        guard safeToKeepAwake else { throw Failure.unsafeConditions }
        if ownsOverride {
            guard try sleepDisabled() else { throw Failure.settingChanged }
            return
        }
        try lockJournal()
        defer { if !ownsOverride { unlock() } }
        try restoreJournaledOverride()
        // Refuse to take ownership of a setting enabled by another utility.
        guard try !sleepDisabled() else { throw Failure.alreadyDisabled }
        let fd = open(journal.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.journal }
        let synced = fsync(fd) == 0
        close(fd)
        guard synced else { throw Failure.journal }
        ownsOverride = true
        do {
            _ = try runCommand(["-a", "disablesleep", "1"])
            guard try sleepDisabled() else { throw Failure.verification }
        } catch {
            try? restore()
            throw error
        }
    }

    func restore() throws {
        guard ownsOverride else { return }
        try restoreSetting()
        unlock()
    }

    private func restoreJournaledOverride() throws {
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        ownsOverride = true
        try restoreSetting()
    }

    private func restoreSetting() throws {
        _ = try runCommand(["-a", "disablesleep", "0"])
        guard try !sleepDisabled() else { throw Failure.verification }
        try FileManager.default.removeItem(at: journal)
        ownsOverride = false
    }

    // The free and development jobs have different launchd labels but share the
    // system-wide power setting and journal. Hold the lock through restoration.
    private func lockJournal() throws {
        guard lock == nil else { return }
        let fd = open(journal.appendingPathExtension("lock").path,
                      O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.journal }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw Failure.busy
        }
        lock = fd
    }

    private func unlock() {
        guard let lock else { return }
        close(lock)
        self.lock = nil
    }

    var safeToKeepAwake: Bool { conditions() }

    private static func checkConditions() -> Bool {
        guard ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical else { return false }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            else { return false }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
               description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue {
                guard let current = description[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = description[kIOPSMaxCapacityKey] as? Int,
                      maximum > 0, Double(current) / Double(maximum) > 0.15 else { return false }
            }
        }
        return true
    }

    private func sleepDisabled() throws -> Bool {
        let output = try runCommand(["-g"])
        guard let line = output.split(separator: "\n").first(where: {
            $0.split(whereSeparator: \.isWhitespace).first == "SleepDisabled"
        }), let value = line.split(whereSeparator: \.isWhitespace).last,
        value == "0" || value == "1" else { throw Failure.verification }
        return value == "1"
    }

    private static func runPMSet(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Bounded execution: a stuck utility cannot stall lease expiry forever.
        let deadline = ContinuousClock.now + .seconds(3)
        while process.isRunning && ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.command }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    enum Failure: String, Error {
        case unsafeConditions = "Closed-lid mode stopped: battery is at or below 15%, or thermal pressure is high."
        case alreadyDisabled = "Another utility already disabled system sleep. Turn that off before using Notchium closed-lid mode."
        case settingChanged = "System sleep settings changed outside Notchium."
        case busy = "Another Notchium helper is using closed-lid mode."
        case journal = "Could not create the sleep-recovery journal."
        case verification = "Could not verify the system sleep setting."
        case command = "macOS rejected the power-setting change."
    }
}
