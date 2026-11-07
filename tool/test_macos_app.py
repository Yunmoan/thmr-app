import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from macos_app import macho_files, sign_app, validate_entitlements, verify_app


class MacDistributionTests(unittest.TestCase):
    def test_rejects_original_crash_entitlements_even_with_empty_groups(self):
        with self.assertRaisesRegex(ValueError, "keychain-access-groups"):
            validate_entitlements({"keychain-access-groups": []})
        with self.assertRaisesRegex(ValueError, "get-task-allow"):
            validate_entitlements({"com.apple.security.get-task-allow": True})
        for name in ("Release", "DebugProfile"):
            data = plistlib.loads(Path(f"macos/Runner/{name}.entitlements").read_bytes())
            self.assertNotIn("keychain-access-groups", data)
        validate_entitlements(plistlib.loads(Path("macos/Runner/Release.entitlements").read_bytes()))

    def make_app(self, directory):
        app = Path(directory) / "THMR.app"
        for name in ("Contents/MacOS/THMR", "Contents/Frameworks/Test.framework/Versions/A/Test"):
            path = app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(bytes.fromhex("cffaedfe") + b"test")
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "cn.yunmoan.thmr.thmrApp",
            "CFBundleShortVersionString": "0.1.5", "CFBundleVersion": "1",
        }))
        return app

    def test_signs_nested_code_before_app_with_only_app_entitlements(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(directory)
            self.assertEqual(len(macho_files(app)), 2)
            with patch("macos_app.subprocess.run") as run:
                sign_app(app)
            commands = [call.args[0] for call in run.call_args_list]
            self.assertEqual(Path(commands[0][-1]).parts[-3:], ("Versions", "A", "Test"))
            self.assertEqual(Path(commands[1][-1]).name, "Test.framework")
            self.assertEqual(commands[-1][-1], str(app))
            self.assertIn("--entitlements", commands[-1])
            self.assertTrue(all("--entitlements" not in cmd for cmd in commands[:-1]))
            self.assertTrue(all("--deep" not in cmd for cmd in commands))

    def test_verification_checks_every_macho_and_both_entitlement_slices(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(directory)
            with patch.dict("os.environ", {}, clear=True), patch("macos_app.subprocess.run") as run:
                run.return_value = subprocess.CompletedProcess([], 0, stdout=b"")
                verify_app(app)
            commands = [call.args[0] for call in run.call_args_list]
            self.assertEqual(sum(cmd[0] == "lipo" for cmd in commands), 2)
            for arch in ("x86_64", "arm64"):
                self.assertEqual(sum("--arch" in cmd and arch in cmd for cmd in commands), 2)
            self.assertTrue(all("--all-architectures" in cmd for cmd in commands if "--verify" in cmd))
            with patch("macos_app.subprocess.run") as run, self.assertRaisesRegex(ValueError, "keychain"):
                run.return_value = subprocess.CompletedProcess([], 0,
                    stdout=plistlib.dumps({"keychain-access-groups": []}))
                verify_app(app)


if __name__ == "__main__":
    unittest.main()
