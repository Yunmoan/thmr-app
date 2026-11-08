"""Exercise shipped Linux scripts in temporary app/XDG directories."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP_ID = 'cn.yunmoan.thmr.thmr_app'


@unittest.skipUnless(sys.platform.startswith('linux'), 'Linux distribution scripts')
class LinuxDistributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='thmr distribution ')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.app = self.base / '中文 app "quote" $cash `tick` %radio \\ album'
        self.app.mkdir()
        self.data = self.base / 'xdg data'
        self.env = dict(os.environ, XDG_DATA_HOME=str(self.data))
        self.probe = self.base / 'launch-probe'
        self.env['THMR_LAUNCH_PROBE'] = str(self.probe)
        for source, name in [('launch.sh', 'thmr'),
                             ('install-desktop.sh', 'install-desktop.sh'),
                             ('uninstall-desktop.sh', 'uninstall-desktop.sh')]:
            shutil.copy2(ROOT / 'tool/linux' / source, self.app / name)
        self.fake_executable('thmr_app',
            'printf "%s\\n" "$0" "$@" > "$THMR_LAUNCH_PROBE"\n')
        self.fake_executable('thmr_runtime_check', 'exit 0\n')
        icons = self.app / 'data/flutter_assets/assets/icons'
        icons.mkdir(parents=True)
        shutil.copy2(ROOT / 'assets/icons/icon-512.png', icons)
        self.entry = self.data / f'applications/{APP_ID}.desktop'

    def fake_executable(self, name, body):
        path = self.app / name
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)
        return path

    def run_script(self, name, *args):
        return subprocess.run([str(self.app / name), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_menu_install_launch_and_idempotent_uninstall(self):
        try:
            from gi.repository import Gio
        except ImportError:
            self.skipTest('PyGObject is required to validate desktop Exec parsing')
        # Avoid ldd on the shell fixture; the real bundle is checked separately.
        self.fake_executable('thmr',
            'printf "%s\\n" "$0" "$@" > "$THMR_LAUNCH_PROBE"\n')
        result = self.run_script('install-desktop.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        if shutil.which('desktop-file-validate'):
            subprocess.run(['desktop-file-validate', str(self.entry)], check=True)
        app = Gio.DesktopAppInfo.new_from_filename(str(self.entry))
        self.assertIsNotNone(app)
        context = Gio.AppLaunchContext()
        context.setenv('THMR_LAUNCH_PROBE', str(self.probe))
        self.assertTrue(app.launch([], context))
        for _ in range(100):
            if self.probe.exists():
                break
            time.sleep(0.01)
        self.assertEqual(self.probe.read_text().splitlines()[0],
                         str(self.app / 'thmr'))
        self.assertEqual(self.run_script('install-desktop.sh').returncode, 0)
        self.assertEqual(self.run_script('uninstall-desktop.sh').returncode, 0)
        self.assertFalse(self.entry.exists())
        self.assertFalse((self.data / f'icons/hicolor/512x512/apps/{APP_ID}.png').exists())
        self.assertTrue((self.app / 'thmr_app').exists())
        self.assertEqual(self.run_script('uninstall-desktop.sh').returncode, 0)

    def test_scripts_preserve_an_unmanaged_menu_entry(self):
        self.entry.parent.mkdir(parents=True)
        self.entry.write_text('[Desktop Entry]\nName=User custom entry\n')
        original = self.entry.read_bytes()
        self.assertNotEqual(self.run_script('install-desktop.sh').returncode, 0)
        self.assertNotEqual(self.run_script('uninstall-desktop.sh').returncode, 0)
        self.assertEqual(self.entry.read_bytes(), original)

    def test_launcher_checks_libraries_and_preserves_arguments(self):
        fake_bin = self.base / 'bin'
        fake_bin.mkdir()
        ldd = fake_bin / 'ldd'
        ldd.write_text('#!/bin/sh\nexit 0\n')
        ldd.chmod(0o755)
        self.env['PATH'] = f'{fake_bin}:{self.env["PATH"]}'
        self.assertEqual(self.run_script('thmr', '--check-runtime').returncode, 0)
        self.assertFalse(self.probe.exists())
        result = self.run_script('thmr', '--thmr-update-ack', 'path with spaces',
                                 '--thmr-update-token', 'abc')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.probe.read_text().splitlines()[1:],
                         ['--thmr-update-ack', 'path with spaces',
                          '--thmr-update-token', 'abc'])
        self.probe.unlink()
        ldd.write_text('#!/bin/sh\nprintf "%s\\n" "libgtk-3.so.0 => not found"\n')
        result = self.run_script('thmr')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('libgtk-3.so.0', result.stderr)
        self.assertFalse(self.probe.exists())
        ldd.write_text('#!/bin/sh\nexit 0\n')
        self.fake_executable('thmr_runtime_check',
                             'printf "%s\\n" "missing libmpv2" >&2\nexit 1\n')
        result = self.run_script('thmr')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('libmpv2', result.stderr)
        self.assertFalse(self.probe.exists())


if __name__ == '__main__':
    unittest.main()
