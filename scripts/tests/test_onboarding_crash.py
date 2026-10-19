#!/usr/bin/env python3
"""Compile the real setup store and verify committed records survive SIGKILL.

Only a disposable directory and a unique, read-only preference suite are used.
No application, TCC database, Clipboard history, or Keychain item is accessed.
"""
import os
from pathlib import Path
import signal
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
HARNESS = r'''
import Darwin
import Foundation
import NotchiumCore

@main struct CrashHarness {
    @MainActor static func main() throws {
        let mode = CommandLine.arguments[1]
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        let preferences = UserDefaults(suiteName: "Notchium.CrashTests." + directory.lastPathComponent)!
        let store = OnboardingStore(preferences: preferences, supportDirectory: directory)
        if mode == "partial" || mode == "complete" {
            var state = OnboardingState()
            state.step = mode == "complete" ? .ready : .permissions
            state.currentPermission = .camera
            state.clipboardChoice = false
            state.reviewed = [.systemAudio, .files]
            if mode == "complete" { state.completion = .userCompleted }
            try store.save(state)
            kill(getpid(), SIGKILL)
            fatalError("SIGKILL must terminate the disposable process")
        }
        for _ in 0..<10 {
            guard let saved = try store.load() else { fatalError("Missing setup record") }
            precondition(saved.currentPermission == .camera)
            precondition(saved.clipboardChoice == false)
            precondition(saved.reviewed == [.systemAudio, .files])
            precondition(saved.requiresOnboarding == (mode == "check-partial"))
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="notchium-onboarding-crash-", dir="/private/tmp") as raw:
        temporary = Path(raw)
        environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(temporary / "modules"))
        subprocess.run([
            "swiftc", "-swift-version", "6", "-emit-library", "-emit-module", "-module-name", "NotchiumCore",
            "-emit-module-path", str(temporary / "NotchiumCore.swiftmodule"),
            str(ROOT / "NotchiumPackage/Sources/NotchiumCore/OnboardingState.swift"),
            "-o", str(temporary / "libNotchiumCore.dylib"),
        ], check=True, env=environment)
        harness = temporary / "main.swift"
        harness.write_text(HARNESS)
        executable = temporary / "crash-harness"
        subprocess.run([
            "swiftc", "-swift-version", "6", "-parse-as-library", "-I", str(temporary),
            "-L", str(temporary), "-lNotchiumCore", "-Xlinker", "-rpath", "-Xlinker", str(temporary),
            str(ROOT / "NotchiumPackage/Sources/NotchiumPersistence/OnboardingStore.swift"),
            str(harness), "-o", str(executable),
        ], check=True, env=environment)
        for mode in ("partial", "complete"):
            directory = temporary / mode
            result = subprocess.run([str(executable), mode, str(directory)], env=environment)
            assert result.returncode == -signal.SIGKILL, result.returncode
            subprocess.run([str(executable), "check-" + mode, str(directory)], check=True, env=environment)
        print("PASS: partial and completed atomic setup records survive SIGKILL and ten subsequent reads each.")


if __name__ == "__main__":
    main()
