"""Exercise the real OS installer helpers against isolated fake app bundles."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class UpdateHelperTests(unittest.TestCase):
    def run_scenario(self, succeeds):
        with tempfile.TemporaryDirectory(prefix="thmr update smoke-") as temporary:
            parent = Path(temporary).resolve()
            token = "ab" * 32
            target = parent / "THMR"
            stage = parent / f".thmr-update-{token}"
            backup = parent / f".thmr-backup-{token}"
            tx = parent / "transaction"
            for directory in (target, stage, tx):
                directory.mkdir()
            (target / "marker").write_text("old")
            (stage / "marker").write_text("new")
            plan = dict(parent=str(parent), target=str(target), stage=str(stage),
                        backup=str(backup), ack=str(tx / "ack"), ready=str(tx / "ready"),
                        result=str(tx / "result.json"), processId=2147483000,
                        token=token, timeout=2, identity="0.2.0+2")
            if os.name == "nt":
                csc = Path(os.environ["WINDIR"]) / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
                if not csc.exists():
                    self.skipTest("C# fixture compiler is unavailable")
                for directory, good in ((target, False), (stage, succeeds)):
                    (directory / "data/flutter_assets").mkdir(parents=True)
                    source = tx / (directory.name + ".cs")
                    source.write_text('using System; using System.IO; using System.Reflection; '
                        '[assembly: AssemblyInformationalVersion("0.2.0+2")] '
                        'class Fixture { static void Main(string[] args) { '
                        + ('if(args.Length==4) File.WriteAllText(args[1],args[3]);' if good else '')
                        + ' } }')
                    subprocess.run([str(csc), "/nologo", "/target:winexe",
                        f"/out:{directory / 'thmr_app.exe'}", str(source)], check=True, capture_output=True)
                plan_path = tx / "plan.json"
                plan_path.write_text(json.dumps(plan), encoding="utf-8")
                command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                           "-File", str(ROOT / "assets/updater/install_windows.ps1"), "-PlanPath", str(plan_path)]
            else:
                for directory, good in ((target, False), (stage, succeeds)):
                    exe = directory / "thmr_app"
                    exe.write_text('#!/bin/sh\n' + ('[ "$#" = 4 ] && printf "%s" "$4" > "$2"\n' if good else 'exit 0\n'))
                    exe.chmod(0o755)
                command = ["/bin/sh", str(ROOT / "assets/updater/install_unix.sh"), str(plan["processId"]),
                           str(target), str(stage), str(backup), plan["ack"], token, "thmr_app",
                           plan["result"], plan["ready"], "2", "linux"]
            result = subprocess.run(command, capture_output=True, text=True, timeout=30)
            status = json.loads(Path(plan["result"]).read_text(encoding="utf-8-sig"))
            self.assertEqual(status["status"], "success" if succeeds else "rollback", result.stderr)
            self.assertEqual((target / "marker").read_text(), "new" if succeeds else "old")
            self.assertFalse(backup.exists())
            self.assertEqual(result.returncode, 0 if succeeds else 1)

    def test_successful_start_commits_update(self):
        self.run_scenario(True)

    def test_failed_start_restores_previous_bundle(self):
        self.run_scenario(False)

    def test_helper_rejects_paths_outside_the_installation_parent(self):
        with tempfile.TemporaryDirectory(prefix="thmr-path-test-") as temporary:
            root = Path(temporary).resolve()
            parent = root / "install"
            parent.mkdir()
            target = parent / "THMR"
            target.mkdir()
            (target / "marker").write_text("untouched")
            external = root / ".thmr-backup-external"
            external.mkdir()
            (external / "marker").write_text("do not touch")
            stage = parent / ".thmr-update-test"
            stage.mkdir()
            plan = dict(parent=str(parent), target=str(target), stage=str(stage),
                backup=str(external), ack=str(root / "ack"), ready=str(root / "ready"),
                result=str(root / "result"), processId=2147483000, token="ab" * 32,
                timeout=2, identity="0.2.0+2")
            if os.name == "nt":
                plan_path = root / "plan.json"
                plan_path.write_text(json.dumps(plan))
                command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                    "-File", str(ROOT / "assets/updater/install_windows.ps1"), "-PlanPath", str(plan_path)]
            else:
                command = ["/bin/sh", str(ROOT / "assets/updater/install_unix.sh"), str(plan["processId"]),
                    str(target), str(stage), str(external), plan["ack"], plan["token"], "thmr_app",
                    plan["result"], plan["ready"], "2", "linux"]
            result = subprocess.run(command, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((external / "marker").read_text(), "do not touch")
            self.assertEqual((target / "marker").read_text(), "untouched")


if __name__ == "__main__":
    unittest.main()
