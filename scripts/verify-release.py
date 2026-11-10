#!/usr/bin/env python3
"""Fail closed on unexpected files, signing, paths, secrets, or Mach-O links."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys


SECRET_PATTERNS = (
    rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})",
    rb"AKIA[0-9A-Z]{16}",
    rb"sk-(?:proj-)?[A-Za-z0-9_-]{32,}",
    rb"(?i)(?:client_secret|access_token|refresh_token|password)\s*[=:]\s*[\"'][A-Za-z0-9_+/-]{16,}[\"']",
)
UNWANTED_SUFFIXES = (
    ".p12", ".pfx", ".pem", ".key", ".mobileprovision", ".provisionprofile",
    ".xctest", ".dSYM", ".profraw", ".profdata", ".trace", ".patch", ".log",
    ".xcresult", ".swift", ".swiftmodule", ".swiftdoc", ".o",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.STDOUT, text=True)


def scan_bytes(data, label, paths=False):
    # Only report the file/category, never the matching value.
    for pattern in SECRET_PATTERNS:
        require(re.search(pattern, data) is None, f"Possible embedded secret: {label}")
    if paths:
        require(b"/Users/" not in data, f"Developer home path: {label}")
        require(re.search(rb"/(?:private/)?(?:tmp|var/folders)/", data) is None,
                f"Temporary build path: {label}")


def scan_source(root):
    count = 0
    for directory in ("Config", "Helpers", "Notchium", "NotchiumPackage/Sources"):
        for path in sorted((root / directory).rglob("*")):
            if path.is_file():
                require(not path.is_symlink(), f"Source symlink: {path.relative_to(root)}")
                require(not path.name.startswith(".env"), "Environment file in production sources")
                scan_bytes(path.read_bytes(), str(path.relative_to(root)))
                count += 1
    print(f"Production source secret scan passed: {count} files (heuristic, not a guarantee).")


LID_AWAKE_LABEL = "com.marcusyu.notchium.lid-awake-free"
LID_AWAKE_HELPER = "Contents/Library/HelperTools/NotchiumLidAwake"
LID_AWAKE_PLIST = {
    "Label": LID_AWAKE_LABEL,
    "BundleProgram": LID_AWAKE_HELPER,
    "MachServices": {LID_AWAKE_LABEL: True},
    "RunAtLoad": True,
    "KeepAlive": True,
    "ThrottleInterval": 3,
}


def verify_lid_awake_helper(app):
    """The only privileged component: exactly one reviewed daemon and its exact launchd job."""
    daemons = app / "Contents/Library/LaunchDaemons"
    require(daemons.is_dir() and sorted(p.name for p in daemons.iterdir()) == [f"{LID_AWAKE_LABEL}.plist"],
            "Unexpected launch daemon inventory")
    with (daemons / f"{LID_AWAKE_LABEL}.plist").open("rb") as stream:
        job = plistlib.load(stream)
    # Exact equality: no ProgramArguments, environment, user, sockets or extra keys.
    require(job == LID_AWAKE_PLIST, "Unexpected closed-lid launchd job")
    helper = app / LID_AWAKE_HELPER
    require(helper.is_file() and not helper.is_symlink(), "Closed-lid helper is missing")
    tools = app / "Contents/Library/HelperTools"
    require(sorted(p.name for p in tools.iterdir()) == ["NotchiumLidAwake"], "Unexpected helper tool inventory")
    signature = run("/usr/bin/codesign", "-dvv", str(helper))
    require(f"Identifier={LID_AWAKE_LABEL}" in signature, "Closed-lid helper has an unexpected signing identifier")


def verify_app(app, version, build):
    require(app.name == "Notchium.app", "Unexpected app name")
    require(not app.is_symlink(), "App must not be a symlink")
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    expected = {
        "CFBundleIdentifier": "com.marcusyu.notchium",
        "CFBundleDisplayName": "Notchium",
        "CFBundleExecutable": "Notchium",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "LSMinimumSystemVersion": "26.0",
        "LSUIElement": True,
    }
    for key, value in expected.items():
        require(info.get(key) == value, f"Unexpected {key}")
    # The microphone is requested only by Teleprompter's voice modes, on an explicit Start.
    for key in ("NSAppleEventsUsageDescription", "NSCameraUsageDescription", "NSCalendarsFullAccessUsageDescription",
                "NSRemindersFullAccessUsageDescription", "NSAudioCaptureUsageDescription",
                "NSDesktopFolderUsageDescription", "NSDownloadsFolderUsageDescription",
                "NSDocumentsFolderUsageDescription", "NSMicrophoneUsageDescription"):
        require(isinstance(info.get(key), str) and len(info[key]) > 15, f"Missing {key}")
    resources = app / "Contents/Resources"
    require((resources / "LICENSE").is_file(), "Missing project license")
    require((resources / "THIRD_PARTY_NOTICES.md").is_file(), "Missing notices")
    require(any(app.rglob("Assets.car")), "Missing compiled media/app assets")
    verify_lid_awake_helper(app)
    require(not any(app.rglob("*.appex")), "Unexpected extension")
    machos = []
    for path in sorted(app.rglob("*")):
        relative = str(path.relative_to(app))
        require(path.name not in (".DS_Store", ".git", "default.profraw") and
                not path.name.startswith(".env") and
                not path.name.endswith(UNWANTED_SUFFIXES), f"Unexpected artifact file: {relative}")
        if path.is_symlink():
            require(path.resolve().is_relative_to(app.resolve()), f"Escaping bundle symlink: {relative}")
            continue
        mode = path.stat().st_mode
        require(not mode & (stat.S_IWGRP | stat.S_IWOTH | stat.S_ISUID | stat.S_ISGID),
                f"Unsafe permissions: {relative}")
        if not path.is_file():
            continue
        data = path.read_bytes()
        scan_bytes(data, relative, paths=True)
        description = run("/usr/bin/file", "-b", str(path))
        if "Mach-O" not in description:
            continue
        machos.append(relative)
        require(run("/usr/bin/lipo", "-archs", str(path)).split() == ["arm64"],
                f"Unexpected architecture: {relative}")
        links = run("/usr/bin/otool", "-L", str(path)).splitlines()[1:]
        for line in links:
            library = line.strip().split(" (", 1)[0]
            require(library.startswith(("/System/Library/", "/usr/lib/")),
                    f"Unreviewed non-system dependency: {relative}")
        for section in run("/usr/bin/otool", "-l", str(path)).split("Load command"):
            if "cmd LC_BUILD_VERSION" in section:
                require(re.search(r"\bminos 26\.0\b", section), f"Unexpected Mach-O deployment target: {relative}")
        signature = run("/usr/bin/codesign", "-dvv", str(path))
        require("Signature=adhoc" in signature and "TeamIdentifier=not set" in signature,
                f"Certificate-backed signing detected: {relative}")
        require("runtime" not in signature, f"Unexpected Hardened Runtime policy: {relative}")
        entitlements = run("/usr/bin/codesign", "-d", "--entitlements", "-", str(path))
        require("<key>" not in entitlements, f"Unexpected free-build entitlement: {relative}")
    require(machos == [LID_AWAKE_HELPER, "Contents/MacOS/Notchium"], "Unexpected executable inventory")
    binary = (app / "Contents/MacOS/Notchium").read_bytes()
    for marker in (b"Notchium launched; bundle=", b"Initial isMenuBarExtraInserted=true",
                   b"--notchium-stage11-fixture", b"--ui-testing", b"notchium-fixture://",
                   b"--notchium-onboarding-fixture", b"--notchium-setup-denied", b"--notchium-setup-spotify-denied", b"Notchium.SetupUITests.",
                   b"default.profraw", b"__llvm_profile", b"__llvm_covmap"):
        require(marker not in binary, "Debug/fixture marker in Release executable")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    print(json.dumps({"version": version, "build": build, "minimum_macos": "26.0",
                      "architectures": ["arm64"], "signing": "ad-hoc; no trusted identity",
                      "entitlements": [], "executables": machos,
                      "launch_daemons": [LID_AWAKE_LABEL]}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--build")
    args = parser.parse_args()
    require(args.source is not None or args.app is not None, "Select --source or --app")
    if args.source:
        scan_source(args.source)
    if args.app:
        require(args.version and args.build, "App verification requires --version and --build")
        verify_app(args.app, args.version, args.build)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Subprocess output stays in private build logs; do not echo possible values.
        print(f"Release verification failed: {type(error).__name__}: "
              f"{error if isinstance(error, ValueError) else 'tool/file operation failed'}", file=sys.stderr)
        sys.exit(1)
