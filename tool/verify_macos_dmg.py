"""Check the final read-only DMG, including its actual bundled app identity."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

from macos_app import verify_app


def verify(image):
    subprocess.run(["hdiutil", "verify", image], check=True)
    with tempfile.TemporaryDirectory(prefix="thmr-dmg-check-") as mount:
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                        "-mountpoint", mount, image], check=True)
        try:
            root = Path(mount)
            assert (root / ".DS_Store").is_file(), "Missing Finder layout"
            assert (root / ".background/background.png").is_file(), "Missing guide background"
            applications = root / "Applications"
            assert applications.is_symlink() and applications.resolve() == Path("/Applications")
            app = root / "THMR.app"
            with (app / "Contents/Info.plist").open("rb") as source:
                info = plistlib.load(source)
            assert info["CFBundleIdentifier"] == "cn.yunmoan.thmr.thmrApp"
            if version := os.environ.get("CLIENT_VERSION"):
                assert info["CFBundleShortVersionString"] == version.split("-")[0]
            if build := os.environ.get("CLIENT_BUILD_NUMBER"):
                assert info["CFBundleVersion"] == build
            # Exercise the installed copy, exactly as a user dragging to Applications.
            with tempfile.TemporaryDirectory(prefix="thmr-installed-check-") as installed:
                target = Path(installed) / "THMR.app"
                subprocess.run(["ditto", str(app), str(target)], check=True)
                verify_app(target, launch=True)
            print(f"Verified DMG: {info['CFBundleShortVersionString']}+{info['CFBundleVersion']}")
        finally:
            subprocess.run(["hdiutil", "detach", mount], check=True)


if __name__ == "__main__":
    verify(sys.argv[1])
