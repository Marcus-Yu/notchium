#!/usr/bin/env python3
"""Regression checks for release guardrails, using isolated temporary files."""

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("release_verifier", Path(__file__).parents[1] / "verify-release.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class ReleaseSafetyTests(unittest.TestCase):
    def test_secret_findings_do_not_echo_values(self):
        secret = b"ghp_" + b"a" * 36
        with self.assertRaises(ValueError) as result:
            verifier.scan_bytes(secret, "resource.txt")
        self.assertNotIn(secret.decode(), str(result.exception))
        self.assertIn("resource.txt", str(result.exception))

    def test_developer_and_temporary_paths_are_rejected(self):
        for path in (b"/Users/example/project", b"/private/tmp/build/source", b"/var/folders/test"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                verifier.scan_bytes(path, "binary", paths=True)

    def test_ordinary_runtime_strings_are_allowed(self):
        verifier.scan_bytes(b"access_token refresh_token https://api.spotify.com/v1/me/player", "binary")

    def test_source_secret_and_symlink_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Notchium"
            source.mkdir()
            file = source / "credential.txt"
            file.write_bytes(b"-----BEGIN PRIVATE KEY-----")
            with self.assertRaises(ValueError):
                verifier.scan_source(root)
            file.unlink()
            (source / "outside").symlink_to("/etc/passwd")
            with self.assertRaises(ValueError):
                verifier.scan_source(root)

    def test_bundle_symlink_is_rejected_before_following_it(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Notchium.app"
            app.symlink_to("/Applications", target_is_directory=True)
            with self.assertRaises(ValueError):
                verifier.verify_app(app, "1.0.0", "2")


class ReleaseCommandTests(unittest.TestCase):
    """Exercise preflight failures without compiling, packaging, or changing Git."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        shutil.copy2(Path(__file__).parents[1] / "release.sh", self.root / "scripts/release.sh")
        (self.root / "Config").mkdir()
        (self.root / "Config/Shared.xcconfig").write_text(
            "MARKETING_VERSION = 1.0.0\nCURRENT_PROJECT_VERSION = 2\n")
        (self.root / "docs/releases").mkdir(parents=True)
        for name in ("LICENSE", "THIRD_PARTY_NOTICES.md", "docs/releases/1.0.0.md"):
            (self.root / name).write_text("Test release fixture\n")
        binary = self.root / "bin"
        binary.mkdir()
        scripts = {
            "git": '''#!/bin/sh
case "$1" in
rev-parse)
    case "$2" in
    HEAD) echo 0123456789abcdef ;;
    *) [ "$TEST_TAG_PRESENT" = 1 ] || exit 1; echo 0123456789abcdef ;;
    esac ;;
status) [ "$TEST_DIRTY" != 1 ] || echo ' M production.swift' ;;
tag) [ "$TEST_OLD_BUILD" = 1 ] || exit 0; echo v0.9.0 ;;
show) echo 'CURRENT_PROJECT_VERSION = 2' ;;
*) exit 90 ;;
esac
''',
            "df": "#!/bin/sh\necho 'Filesystem Blocks Used Available'\necho 'fixture 0 0 0'\n",
        }
        for name, source in scripts.items():
            path = binary / name
            path.write_text(source)
            path.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                                TEST_TAG_PRESENT="0", TEST_DIRTY="0", TEST_OLD_BUILD="0")

    def stopped_with(self, message, *options, **environment):
        result = subprocess.run(["/bin/bash", str(self.root / "scripts/release.sh"), "1.0.0", *options],
                                env=dict(self.environment, **environment), text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)
        self.assertFalse((self.root / "dist").exists())

    def test_candidate_rejects_dirty_source(self):
        self.stopped_with("Commit reviewed source", "--candidate", TEST_DIRTY="1")

    def test_candidate_does_not_require_or_create_tag(self):
        self.stopped_with("At least 1.5 GiB", "--candidate")

    def test_normal_release_still_requires_tag(self):
        self.stopped_with("Tag v1.0.0 must already point to HEAD")

    def test_tagged_release_reaches_remaining_preflight(self):
        self.stopped_with("At least 1.5 GiB", TEST_TAG_PRESENT="1")

    def test_candidate_keeps_build_number_gate(self):
        self.stopped_with("Build number must exceed", "--candidate", TEST_OLD_BUILD="1")

    def test_candidate_and_preview_are_mutually_exclusive(self):
        for options in (("--candidate", "--preview"), ("--preview", "--candidate")):
            with self.subTest(options=options):
                self.stopped_with("Choose either --preview or --candidate", *options)


if __name__ == "__main__":
    unittest.main()
