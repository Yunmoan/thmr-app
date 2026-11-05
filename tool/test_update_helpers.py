"""Exercise the real OS installer helpers against isolated fake app bundles."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent


class UpdateHelperTests(unittest.TestCase):
    def run_scenario(self, succeeds, native_launcher=False, cache_source=False, simulate_uac=False):
        with tempfile.TemporaryDirectory(prefix="thmr update smoke-") as temporary:
            parent = Path(temporary).resolve()
            token = "ab" * 32
            target = parent / "THMR"
            stage = parent / f".thmr-update-{token}"
            backup = parent / f".thmr-backup-{token}"
            tx = parent / "transaction"
            for directory in (target, stage, tx):
                directory.mkdir()
            payload = stage
            if cache_source:
                stage.rmdir()
                payload = tx / 'payload'
                payload.mkdir()
            (target / "marker").write_text("old")
            (payload / "marker").write_text("new")
            plan = dict(parent=str(parent), target=str(target), stage=str(stage),
                        backup=str(backup), ack=str(tx / "ack"), ready=str(tx / "ready"),
                        result=str(tx / "result.json"), processId=2147483000,
                        token=token, timeout=2, identity="0.2.0+2")
            if cache_source:
                plan.update(source=str(payload), requiresElevation=simulate_uac)
            if os.name == "nt":
                csc = Path(os.environ["WINDIR"]) / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
                if not csc.exists():
                    self.skipTest("C# fixture compiler is unavailable")
                for directory, good in ((target, False), (payload, succeeds)):
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
                helper = ROOT / 'assets/updater/install_windows.ps1'
                if native_launcher or simulate_uac:
                    # Mock only the OS elevation boundary; exercise the real
                    # supervisor/worker protocol without interacting with UAC.
                    helper = tx / 'install.ps1'
                    helper_source = (ROOT / 'assets/updater/install_windows.ps1').read_text()
                    if simulate_uac:
                        helper_source = helper_source.replace(' -Verb RunAs', '')
                    # Instrument only the PID so cleanup waits for the real
                    # helper process to exit after its final transaction write.
                    helper_source = helper_source.replace('$plan = $null', "$plan = $null\nif (-not $ElevatedWorker) { [IO.File]::WriteAllText((Join-Path $transaction 'helper.pid'), [string]$PID) }")
                    helper.write_text(helper_source, encoding='utf-8')
                command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                           "-File", str(helper), "-PlanPath", str(plan_path)]
                if native_launcher:
                    dart = shutil.which('dart')
                    if not dart:
                        self.skipTest('Dart SDK is unavailable')
                    if Path(dart).suffix.lower() in ['.bat', '.cmd']:
                        dart = str(Path(dart).parent / 'cache/dart-sdk/bin/dart.exe')
                    command = [dart, 'run', str(ROOT / 'tool/run_windows_update_helper.dart'), str(helper), str(plan_path)]
            else:
                for directory, good in ((target, False), (stage, succeeds)):
                    exe = directory / "thmr_app"
                    exe.write_text('#!/bin/sh\n' + ('[ "$#" = 4 ] && printf "%s" "$4" > "$2"\n' if good else 'exit 0\n'))
                    exe.chmod(0o755)
                command = ["/bin/sh", str(ROOT / "assets/updater/install_unix.sh"), str(plan["processId"]),
                           str(target), str(stage), str(backup), plan["ack"], token, "thmr_app",
                           plan["result"], plan["ready"], "2", "linux"]
            result = subprocess.run(command, capture_output=True, text=True, timeout=50)
            if native_launcher:
                deadline = time.monotonic() + 15
                while (not Path(plan['result']).exists() or not (tx / 'helper.done').exists()) and time.monotonic() < deadline:
                    time.sleep(.1)
                import ctypes
                kernel = ctypes.WinDLL('kernel32', use_last_error=True)
                kernel.OpenProcess.restype = ctypes.c_void_p
                kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
                kernel.CloseHandle.argtypes = [ctypes.c_void_p]
                helper_pid = int((tx / 'helper.pid').read_text())
                handle = kernel.OpenProcess(0x100000, False, helper_pid)
                if handle:
                    try:
                        self.assertEqual(kernel.WaitForSingleObject(handle, 5000), 0)
                    finally:
                        kernel.CloseHandle(handle)
            status = json.loads(Path(plan["result"]).read_text(encoding="utf-8-sig"))
            self.assertEqual(status["status"], "success" if succeeds else "rollback", result.stderr)
            self.assertEqual((target / "marker").read_text(), "new" if succeeds else "old")
            self.assertFalse(backup.exists())
            self.assertEqual(result.returncode, 0 if succeeds or native_launcher else 1)

    def test_successful_start_commits_update(self):
        self.run_scenario(True)

    def test_failed_start_restores_previous_bundle(self):
        self.run_scenario(False)

    @unittest.skipUnless(os.name == 'nt', 'Windows ShellExecute integration')
    def test_native_launcher_survives_gui_exit_and_installs_cached_payload(self):
        self.run_scenario(True, native_launcher=True, cache_source=True)

    @unittest.skipUnless(os.name == 'nt', 'Windows ShellExecute integration')
    def test_native_launcher_survives_gui_exit_and_rolls_back_failed_start(self):
        self.run_scenario(False, native_launcher=True, cache_source=True)

    @unittest.skipUnless(os.name == 'nt', 'Windows elevation protocol')
    def test_supervisor_restarts_in_original_session_after_worker_install(self):
        self.run_scenario(True, native_launcher=True, cache_source=True, simulate_uac=True)

    @unittest.skipUnless(os.name == 'nt', 'Windows drive-root paths')
    def test_drive_root_is_preserved_when_validating_siblings(self):
        helper = str(ROOT / 'assets/updater/install_windows.ps1').replace("'", "''")
        script = f"""
        $tokens=$null; $errors=$null
        $ast=[System.Management.Automation.Language.Parser]::ParseFile('{helper}',[ref]$tokens,[ref]$errors)
        $ast.FindAll({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Normalize-Directory','Assert-Sibling')}},$false) | ForEach-Object {{ Invoke-Expression $_.Extent.Text }}
        $root=[IO.Path]::GetPathRoot($env:TEMP)
        $parent=Normalize-Directory $root
        if ($parent -ne $root) {{ throw 'Drive root was truncated' }}
        $expected=Join-Path $root '.thmr-update-path-test'
        if ((Assert-Sibling $expected '.thmr-update-') -ne $expected) {{ throw 'Drive-root sibling rejected' }}
        """
        result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)

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
