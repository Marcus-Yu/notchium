#!/usr/bin/env python3
"""Regression checks for release guardrails, using isolated temporary files."""

import importlib.util
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
