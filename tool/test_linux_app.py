#!/usr/bin/env python3
"""Real GTK integration under a private Xvfb display, D-Bus and XDG profile.

Exercises the production tray probe, close policy, shell-host loss/recovery,
single-instance activation, MPRIS registration and tray-menu graceful exit.
Requires PyGObject, Xvfb, dbus-run-session and libX11; never uses the user's bus.
"""
import argparse
import ctypes
import ctypes.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

APP_ID = 'cn.yunmoan.thmr.thmr_app'
MPRIS = 'org.mpris.MediaPlayer2.thmr'
WATCHER = 'org.kde.StatusNotifierWatcher'


class XWindowAttributes(ctypes.Structure):
    _fields_ = [(name, ctypes.c_int) for name in
                ['x', 'y', 'width', 'height', 'border_width', 'depth']] + [
        ('visual', ctypes.c_void_p), ('root', ctypes.c_ulong),
        ('window_class', ctypes.c_int), ('bit_gravity', ctypes.c_int),
        ('win_gravity', ctypes.c_int), ('backing_store', ctypes.c_int),
        ('backing_planes', ctypes.c_ulong), ('backing_pixel', ctypes.c_ulong),
        ('save_under', ctypes.c_int), ('colormap', ctypes.c_ulong),
        ('map_installed', ctypes.c_int), ('map_state', ctypes.c_int),
        ('all_event_masks', ctypes.c_long), ('your_event_mask', ctypes.c_long),
        ('do_not_propagate_mask', ctypes.c_long), ('override_redirect', ctypes.c_int),
        ('screen', ctypes.c_void_p)]


class ClientMessage(ctypes.Structure):
    _fields_ = [('type', ctypes.c_int), ('serial', ctypes.c_ulong),
                ('send_event', ctypes.c_int), ('display', ctypes.c_void_p),
                ('window', ctypes.c_ulong), ('message_type', ctypes.c_ulong),
                ('format', ctypes.c_int), ('data', ctypes.c_long * 5)]


class XEvent(ctypes.Union):
    _fields_ = [('client', ClientMessage), ('padding', ctypes.c_long * 24)]


class Windows:
    def __init__(self):
        self.x = ctypes.CDLL(ctypes.util.find_library('X11'))
        self.x.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x.XOpenDisplay.restype = ctypes.c_void_p
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError('Xvfb display could not be opened')
        self.x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        self.x.XDefaultRootWindow.restype = ctypes.c_ulong
        self.x.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)), ctypes.POINTER(ctypes.c_uint)]
        self.x.XFree.argtypes = [ctypes.c_void_p]
        self.x.XGetWindowAttributes.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                                               ctypes.POINTER(XWindowAttributes)]
        self.x.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
        self.x.XInternAtom.restype = ctypes.c_ulong
        self.x.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int,
                                      ctypes.c_long, ctypes.POINTER(XEvent)]
        self.x.XFlush.argtypes = [ctypes.c_void_p]
        self.x.XCloseDisplay.argtypes = [ctypes.c_void_p]
        self.last_windows = []

    def find(self):
        root, parent = ctypes.c_ulong(), ctypes.c_ulong()
        children, count = ctypes.POINTER(ctypes.c_ulong)(), ctypes.c_uint()
        self.x.XQueryTree(self.display, self.x.XDefaultRootWindow(self.display),
                         ctypes.byref(root), ctypes.byref(parent),
                         ctypes.byref(children), ctypes.byref(count))
        self.last_windows = []
        try:
            for index in range(count.value):
                window = children[index]
                attrs = XWindowAttributes()
                self.x.XGetWindowAttributes(self.display, window, ctypes.byref(attrs))
                self.last_windows.append((window, attrs.width, attrs.height, attrs.map_state))
                # UTF-8 titles need not have a legacy WM_NAME representation.
                # This private display has a single application-sized window.
                if attrs.map_state == 2 and attrs.width >= 430 and attrs.height >= 660:
                    return window
        finally:
            if children:
                self.x.XFree(children)
        return None

    def visible(self, window):
        attributes = XWindowAttributes()
        return bool(self.x.XGetWindowAttributes(self.display, window,
                    ctypes.byref(attributes))) and attributes.map_state == 2

    def close(self, window):
        event = XEvent()
        event.client.type = 33  # ClientMessage
        event.client.send_event = 1
        event.client.display = self.display
        event.client.window = window
        event.client.message_type = self.x.XInternAtom(self.display, b'WM_PROTOCOLS', 0)
        event.client.format = 32
        event.client.data[0] = self.x.XInternAtom(self.display, b'WM_DELETE_WINDOW', 0)
        self.x.XSendEvent(self.display, window, 0, 0, ctypes.byref(event))
        self.x.XFlush(self.display)


def wait_for(predicate, description, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = predicate()
            if result:
                return result
        except Exception:
            pass
        time.sleep(0.05)
    raise AssertionError(f'Timed out: {description}')


def exercise(bundle):
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    host = [False]
    registrations = []
    xml = '''<node><interface name="org.kde.StatusNotifierWatcher">
      <method name="RegisterStatusNotifierItem"><arg type="s" direction="in"/></method>
      <method name="RegisterStatusNotifierHost"><arg type="s" direction="in"/></method>
      <property name="IsStatusNotifierHostRegistered" type="b" access="read"/>
      <property name="ProtocolVersion" type="i" access="read"/>
      <property name="RegisteredStatusNotifierItems" type="as" access="read"/>
    </interface></node>'''
    node = Gio.DBusNodeInfo.new_for_xml(xml)

    def method(connection, sender, path, interface, name, args, invocation):
        if name == 'RegisterStatusNotifierItem':
            registrations.append((sender, args.unpack()[0]))
        invocation.return_value(None)

    def property_value(connection, sender, path, interface, name):
        if name == 'IsStatusNotifierHostRegistered':
            return GLib.Variant('b', host[0])
        if name == 'ProtocolVersion':
            return GLib.Variant('i', 0)
        return GLib.Variant('as', [])

    registration = bus.register_object('/StatusNotifierWatcher', node.interfaces[0],
                                       method, property_value, None)
    owner = Gio.bus_own_name_on_connection(bus, WATCHER, Gio.BusNameOwnerFlags.NONE,
                                           None, None)
    loop = GLib.MainLoop()
    loop_thread = threading.Thread(target=loop.run, daemon=True)
    loop_thread.start()
    windows = Windows()

    def dbus_call(destination, path, interface, name, args=None):
        return bus.call_sync(destination, path, interface, name, args, None,
                              Gio.DBusCallFlags.NONE, 2000, None)

    def player_property(name):
        return dbus_call(MPRIS, '/org/mpris/MediaPlayer2',
            'org.freedesktop.DBus.Properties', 'Get', GLib.Variant('(ss)',
            ('org.mpris.MediaPlayer2.Player', name))).unpack()[0]

    def set_host(available):
        host[0] = available
        bus.emit_signal(None, '/StatusNotifierWatcher',
            'org.freedesktop.DBus.Properties', 'PropertiesChanged',
            GLib.Variant('(sa{sv}as)', (WATCHER,
                {'IsStatusNotifierHostRegistered': GLib.Variant('b', available)}, [])))

    def quit_from_tray():
        sender, item = registrations[-1]
        destination = item if not item.startswith('/') else sender
        item_path = item if item.startswith('/') else '/StatusNotifierItem'
        menu = dbus_call(destination, item_path, 'org.freedesktop.DBus.Properties',
            'Get', GLib.Variant('(ss)', ('org.kde.StatusNotifierItem', 'Menu'))).unpack()[0]
        layout = dbus_call(destination, menu, 'com.canonical.dbusmenu', 'GetLayout',
            GLib.Variant('(iias)', (0, -1, ['label']))).unpack()[1]

        def find_exit(item):
            identity, properties, children = item
            if properties.get('label') == '退出':
                return identity
            for child in children:
                identity = find_exit(child)
                if identity is not None:
                    return identity
            return None

        identity = find_exit(layout)
        if identity is None:
            raise AssertionError('Tray exit menu is missing')
        dbus_call(destination, menu, 'com.canonical.dbusmenu', 'Event',
            GLib.Variant('(isvu)', (identity, 'clicked', GLib.Variant('s', ''), 0)))

    try:
        with tempfile.TemporaryDirectory(prefix='thmr GTK test ') as temporary:
            root = Path(temporary)
            env = dict(os.environ, GIO_USE_VFS='local', GSETTINGS_BACKEND='memory',
                       GTK_USE_PORTAL='0', XDG_CURRENT_DESKTOP='THMRTest',
                       GDK_BACKEND='x11', XDG_SESSION_TYPE='x11')
            env.pop('WAYLAND_DISPLAY', None)
            for key, folder in [('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                                ('XDG_CACHE_HOME', 'cache'), ('TMPDIR', 'tmp')]:
                env[key] = str(root / folder)
                Path(env[key]).mkdir()
            preferences = Path(env['XDG_DATA_HOME']) / APP_ID
            preferences.mkdir()
            (preferences / 'shared_preferences.json').write_text(json.dumps({
                'flutter.closeAction': 'tray', 'flutter.autoPlay': False}))
            with (root / 'app.log').open('w+') as log:
                app = subprocess.Popen([str(bundle / 'thmr')], env=env,
                                       stdout=log, stderr=log)
                try:
                    wait_for(lambda: player_property('CanControl'), 'MPRIS startup')
                    if player_property('CanSeek'):
                        raise AssertionError('Live radio advertises seeking')
                    window = wait_for(windows.find, 'GTK window')
                    wait_for(lambda: registrations, 'AppIndicator registration')
                    windows.close(window)
                    time.sleep(0.5)
                    if app.poll() is not None or not windows.visible(window):
                        raise AssertionError('No-host close did not retain a recoverable window')
                    set_host(True)
                    time.sleep(2.5)  # Production monitor polls every two seconds.
                    windows.close(window)
                    wait_for(lambda: not windows.visible(window), 'hide to usable tray')
                    duplicate = subprocess.run([str(bundle / 'thmr')], env=env,
                                               stdout=log, stderr=log, timeout=10)
                    if duplicate.returncode != 0 or app.poll() is not None:
                        raise AssertionError('Duplicate launch did not preserve original process')
                    wait_for(lambda: windows.visible(window), 'single-instance restoration')
                    windows.close(window)
                    wait_for(lambda: not windows.visible(window), 'second hide')
                    set_host(False)
                    wait_for(lambda: windows.visible(window), 'restore after tray host loss')
                    quit_from_tray()
                    exit_code = app.wait(timeout=8)
                    if exit_code != 0:
                        raise AssertionError(f'Tray exit failed: process returned {exit_code}')
                    print('GTK integration passed: no-host fallback, tray hide, duplicate '
                          'restore, host-loss recovery, MPRIS and graceful exit')
                except Exception:
                    print('Xvfb windows:', windows.last_windows, file=sys.stderr)
                    log.seek(0)
                    print(log.read(), file=sys.stderr)
                    raise
                finally:
                    if app.poll() is None:
                        app.terminate()
                        try:
                            app.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            app.kill()
                            app.wait()
    finally:
        windows.x.XCloseDisplay(windows.display)
        loop.quit()
        loop_thread.join(timeout=2)
        Gio.bus_unown_name(owner)
        bus.unregister_object(registration)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--inside', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    if args.inside:
        exercise(bundle)
    else:
        env = dict(os.environ, GDK_BACKEND='x11', XDG_SESSION_TYPE='x11',
                   XDG_CURRENT_DESKTOP='THMRTest')
        env.pop('WAYLAND_DISPLAY', None)
        subprocess.run(['xvfb-run', '-a', 'dbus-run-session', '--', sys.executable,
                        __file__, str(bundle), '--inside'], check=True, env=env)


if __name__ == '__main__':
    main()
