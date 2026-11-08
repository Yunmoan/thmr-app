#!/usr/bin/env python3
"""Compile the production GIO service and exercise its public D-Bus contract.

Requires a C++ compiler, gio-2.0 development files, dbus-run-session and PyGObject.
Uses an isolated session bus; does not touch the running player or user settings.
"""
import os
from pathlib import Path
import select
import shlex
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
NAME = 'org.mpris.MediaPlayer2.thmr'
PATH = '/org/mpris/MediaPlayer2'
PLAYER = 'org.mpris.MediaPlayer2.Player'
ROOT_INTERFACE = 'org.mpris.MediaPlayer2'


def exercise(binary):
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    process = subprocess.Popen([binary], stdout=subprocess.PIPE, text=True)

    def call(interface, method, args=None):
        return bus.call_sync(NAME, PATH, interface, method, args, None,
                             Gio.DBusCallFlags.NONE, 2000, None)

    def get(name, interface=PLAYER):
        result = call('org.freedesktop.DBus.Properties', 'Get',
                      GLib.Variant('(ss)', (interface, name)))
        return result.unpack()[0]

    try:
        for _ in range(80):
            try:
                if get('Identity', ROOT_INTERFACE):
                    break
            except GLib.Error:
                time.sleep(0.05)
        else:
            raise AssertionError('MPRIS name was not registered')
        assert get('DesktopEntry', ROOT_INTERFACE) == 'cn.yunmoan.thmr.thmr_app'
        assert get('PlaybackStatus') == 'Stopped'
        for name in ['CanGoNext', 'CanGoPrevious', 'CanSeek']:
            assert get(name) is False
        metadata = get('Metadata')
        assert metadata['xesam:title'] == 'Test song'
        assert metadata['xesam:artist'] == ['Test artist']
        assert metadata['mpris:artUrl'] == 'https://example.test/cover.png'
        assert metadata['mpris:length'] == 20000000
        assert metadata['mpris:trackid'].startswith(PATH + '/track/')
        assert get('Position') == 5000000
        signals = []
        subscription = bus.signal_subscribe(
            NAME, 'org.freedesktop.DBus.Properties', 'PropertiesChanged', PATH,
            None, Gio.DBusSignalFlags.NONE,
            lambda *args: signals.append(args[5].unpack()))
        for method, expected in [('Play', 'Playing'), ('Pause', 'Paused'),
                                 ('PlayPause', 'Playing'), ('Stop', 'Stopped')]:
            call(PLAYER, method)
            assert get('PlaybackStatus') == expected
        for method, args in [('Next', None), ('Previous', None),
                             ('Seek', GLib.Variant('(x)', (1000000,))),
                             ('SetPosition', GLib.Variant('(ox)',
                              (metadata['mpris:trackid'], 10000000)))]:
            call(PLAYER, method, args)
            assert get('Position') == 5000000
            assert get('PlaybackStatus') == 'Stopped'
        call('org.freedesktop.DBus.Properties', 'Set', GLib.Variant('(ssv)',
             (PLAYER, 'Volume', GLib.Variant('d', 0.33))))
        assert abs(get('Volume') - 0.33) < 0.0001
        try:
            call('org.freedesktop.DBus.Properties', 'Set', GLib.Variant('(ssv)',
                 (PLAYER, 'Rate', GLib.Variant('d', 2.0))))
        except GLib.Error:
            pass
        else:
            raise AssertionError('Unsupported playback rate was accepted')
        call(ROOT_INTERFACE, 'Raise')
        assert select.select([process.stdout], [], [], 2)[0]
        assert process.stdout.readline().strip() == 'raised'
        context = GLib.MainContext.default()
        for _ in range(50):
            while context.pending():
                context.iteration(False)
            if signals:
                break
            time.sleep(0.01)
        assert any('PlaybackStatus' in changed for _, changed, _ in signals)
        assert all('Position' not in changed for _, changed, _ in signals)
        bus.signal_unsubscribe(subscription)
    finally:
        process.terminate()
        process.wait(timeout=5)
    assert process.returncode == 0
    print('MPRIS integration checks passed')


def main():
    if len(sys.argv) == 3 and sys.argv[1] == '--inside':
        exercise(sys.argv[2])
        return
    flags = shlex.split(subprocess.check_output(
        ['pkg-config', '--cflags', '--libs', 'gio-2.0'], text=True))
    with tempfile.TemporaryDirectory(prefix='thmr-mpris-test-') as directory:
        binary = str(Path(directory) / 'mpris-fixture')
        subprocess.run([os.environ.get('CXX', 'c++'), '-std=c++14', '-Wall',
                        '-Wextra', '-Werror', '-I', str(ROOT / 'linux/runner'),
                        str(ROOT / 'test/native/mpris_fixture.cc'),
                        str(ROOT / 'linux/runner/mpris_service.cc'),
                        '-o', binary, *flags], check=True)
        subprocess.run(['dbus-run-session', '--', sys.executable, __file__,
                        '--inside', binary], check=True)


if __name__ == '__main__':
    main()
