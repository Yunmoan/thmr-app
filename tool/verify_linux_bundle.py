#!/usr/bin/env python3
"""Validate a complete portable Linux bundle and optionally its glibc baseline."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def verify(bundle, max_glibc=None):
    required = ['thmr_app', 'thmr', 'thmr_runtime_check', 'install-desktop.sh',
                'uninstall-desktop.sh', 'README-Linux.md', 'lib/libthmr_mp3.so',
                'data/icudtl.dat', 'data/flutter_assets/version.json',
                'data/flutter_assets/assets/icons/icon-512.png',
                'data/licenses/minimp3/LICENSE', 'lib/libflutter_linux_gtk.so']
    for name in required:
        if not (bundle / name).is_file():
            raise ValueError(f'Incomplete Linux bundle: missing {name}')
    for name in required[:5]:
        if not os.access(bundle / name, os.X_OK):
            raise ValueError(f'Executable permission missing: {name}')
    version = json.loads((bundle / 'data/flutter_assets/version.json').read_text())
    if not version.get('version') or int(version['build_number']) < 0:
        raise ValueError('Invalid client version metadata')
    vendor = ROOT / 'native/vendor/minimp3'
    manifest = json.loads((vendor / 'source.json').read_text())
    for name, expected in manifest['files'].items():
        if hashlib.sha256((vendor / name).read_bytes()).hexdigest() != expected:
            raise ValueError(f'Vendored minimp3 hash mismatch: {name}')
    if (bundle / 'data/licenses/minimp3/LICENSE').read_bytes() != (vendor / 'LICENSE').read_bytes():
        raise ValueError('Bundled decoder license does not match its source')
    decoder = ctypes.CDLL(str((bundle / 'lib/libthmr_mp3.so').resolve()))
    for symbol in ['thmr_mp3_create', 'thmr_mp3_decode', 'thmr_mp3_destroy']:
        getattr(decoder, symbol)
    observed = set()
    for binary in [bundle / 'thmr_app', bundle / 'thmr_runtime_check',
                   *sorted((bundle / 'lib').glob('*.so'))]:
        versions = subprocess.check_output(['readelf', '--version-info',
                                           str(binary)], text=True)
        observed.update(re.findall(r'\bGLIBC_(\d+\.\d+(?:\.\d+)?)\b', versions))
    maximum = max(observed, key=lambda value: tuple(map(int, value.split('.'))))
    if max_glibc and tuple(map(int, maximum.split('.'))) > tuple(map(int, max_glibc.split('.'))):
        raise ValueError(f'Bundle needs glibc {maximum}, exceeds baseline {max_glibc}')
    subprocess.run([str((bundle / 'thmr').resolve()), '--check-runtime'], check=True)
    print(f'Linux bundle verified: {version["version"]}+{version["build_number"]}, '
          f'maximum glibc requirement {maximum}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--max-glibc')
    args = parser.parse_args()
    verify(args.bundle, args.max_glibc)


if __name__ == '__main__':
    main()
