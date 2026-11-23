"""保留 macOS 文件元数据解压最终更新 ZIP，再校验并启动应用。"""
from pathlib import Path
import subprocess
import sys
import tempfile

from macos_app import verify_app


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="thmr-zip-check-") as directory:
        subprocess.run(["ditto", "-x", "-k", sys.argv[1], directory], check=True)
        verify_app(Path(directory) / "THMR.app", launch=True)
