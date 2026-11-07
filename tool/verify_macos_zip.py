"""Extract the final updater ZIP with macOS metadata, then validate and launch it."""
from pathlib import Path
import subprocess
import sys
import tempfile

from macos_app import verify_app


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="thmr-zip-check-") as directory:
        subprocess.run(["ditto", "-x", "-k", sys.argv[1], directory], check=True)
        verify_app(Path(directory) / "THMR.app", launch=True)
