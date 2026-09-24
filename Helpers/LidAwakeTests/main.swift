import Foundation

// No root, helper installation, or real power-setting commands are used here.
let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let journal = folder.appendingPathComponent("recovery")
var disabled = false
var safe = true
var failRestore = false
var writes = [String]()
let command: ([String]) throws -> String = { arguments in
    if arguments == ["-g"] { return "System-wide power settings:\n SleepDisabled\t\(disabled ? 1 : 0)\n" }
    precondition(arguments == ["-a", "disablesleep", "1"] || arguments == ["-a", "disablesleep", "0"])
    let value = arguments.last!
    if failRestore && value == "0" { throw PowerOverride.Failure.command }
    precondition(FileManager.default.fileExists(atPath: journal.path), "Journal must precede setting mutation")
    writes.append(value)
    disabled = value == "1"
    return ""
}
@MainActor func makePower() -> PowerOverride { PowerOverride(journal: journal, runCommand: command, conditions: { safe }) }
func expectFailure(_ work: () throws -> Void) {
    do { try work(); fatalError("Expected rejection") } catch { }
}
let power = makePower()
try power.acquire()
precondition(disabled && power.ownsOverride)
try power.acquire()
precondition(writes == ["1"], "Renewal must not rewrite global settings")
try power.restore()
precondition(!disabled && !power.ownsOverride)
precondition(!FileManager.default.fileExists(atPath: journal.path))
disabled = true
expectFailure { try power.acquire() }
precondition(disabled && !power.ownsOverride, "Do not take ownership from another app")
disabled = false
safe = false
expectFailure { try power.acquire() }
precondition(!disabled)
safe = true
try power.acquire()
// Simulate a helper crash/restart while the override is active.
let restarted = makePower()
try restarted.recover()
precondition(!disabled && !restarted.ownsOverride)
try restarted.acquire()
failRestore = true
expectFailure { try restarted.restore() }
precondition(restarted.ownsOverride && FileManager.default.fileExists(atPath: journal.path))
failRestore = false
try restarted.restore()
precondition(!disabled)
print("PASS: acquire, renewal, release, foreign ownership, safety cutoff, crash recovery, and restoration retry")
