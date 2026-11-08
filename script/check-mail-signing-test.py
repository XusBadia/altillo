#!/usr/bin/env python3
"""Provisioning gate tests; all signing material and tool responses are synthetic."""
import datetime
import importlib.util
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = pathlib.Path(__file__).with_name("check-mail-signing.py")
SPEC = importlib.util.spec_from_file_location("check_mail_signing", SCRIPT)
SIGNING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SIGNING)


class SigningGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="altillo-signing-test-")
        self.addCleanup(self.temporary.cleanup)
        self.app = pathlib.Path(self.temporary.name) / "Altillo.app"
        self.contents = self.app / "Contents"
        self.contents.mkdir(parents=True)
        self.info = {"CFBundleIdentifier": "me.badia.altillo"}
        self.write_info()
        self.identifier = "TESTTEAM.me.badia.altillo"
        self.profile = {
            "UUID": "synthetic-profile",
            "Entitlements": {"com.apple.application-identifier": self.identifier},
            "Platform": ["OSX"],
            "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=30),
            "ProvisionsAllDevices": True,
            "TeamIdentifier": ["TESTTEAM"],
            "DeveloperCertificates": [b"synthetic-certificate"],
        }
        self.signed = {"com.apple.application-identifier": self.identifier}

    def write_info(self):
        (self.contents / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def install_profile(self):
        (self.contents / "embedded.provisionprofile").write_bytes(b"synthetic-profile")

    def mocked_output(self, command, **kwargs):
        return plistlib.dumps(self.profile if command[0] == "security" else self.signed)

    def mocked_run(self, command, **kwargs):
        for argument in command:
            if argument.startswith("--extract-certificates="):
                pathlib.Path(argument.split("=", 1)[1] + "0").write_bytes(b"synthetic-certificate")
        return subprocess.CompletedProcess(command, 0, "", "TeamIdentifier=TESTTEAM\n")

    def test_optional_unconfigured_build_does_not_require_profile(self):
        with patch.object(SIGNING.subprocess, "check_output") as output:
            self.assertIsNone(SIGNING.check(self.app))
            output.assert_not_called()

    def test_private_keychain_release_requires_profile_without_mail_clients(self):
        with self.assertRaisesRegex(ValueError, "Private Keychain access requires"):
            SIGNING.check(self.app, require_profile=True)
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.app), "--require-profile"],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Private Keychain access requires", result.stderr)

    def test_native_mail_client_gate_remains_required_when_requested(self):
        with self.assertRaisesRegex(ValueError, "registered Google and Microsoft"):
            SIGNING.check(self.app, require_clients=True, require_profile=True)

    def test_configured_native_mail_still_requires_profile(self):
        self.info["ALTILLO_GOOGLE_MAIL_CLIENT_ID"] = "123-public.apps.googleusercontent.com"
        self.write_info()
        with self.assertRaisesRegex(ValueError, "Native mail requires an embedded"):
            SIGNING.check(self.app)

    def test_usage_only_release_validates_profile_identity_team_and_certificate(self):
        self.install_profile()
        with patch.object(SIGNING.subprocess, "check_output", side_effect=self.mocked_output), \
                patch.object(SIGNING.subprocess, "run", side_effect=self.mocked_run) as run:
            self.assertEqual(SIGNING.check(self.app, require_profile=True),
                             ("me.badia.altillo", "synthetic-profile"))
            self.assertTrue(any(call.args[0][1:4] == ["--verify", "--deep", "--strict"]
                                for call in run.call_args_list))

    def test_required_profile_does_not_accept_unrelated_identity(self):
        self.install_profile()
        self.signed["com.apple.application-identifier"] = "TESTTEAM.other.app"
        with patch.object(SIGNING.subprocess, "check_output", side_effect=self.mocked_output), \
                patch.object(SIGNING.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "must match this app"):
                SIGNING.check(self.app, require_profile=True)
            run.assert_not_called()

    def test_required_profile_rejects_debugger_entitlement(self):
        self.install_profile()
        self.signed["com.apple.security.get-task-allow"] = True
        with patch.object(SIGNING.subprocess, "check_output", side_effect=self.mocked_output):
            with self.assertRaisesRegex(ValueError, "must not allow debugger"):
                SIGNING.check(self.app, require_profile=True)


if __name__ == "__main__":
    unittest.main()
