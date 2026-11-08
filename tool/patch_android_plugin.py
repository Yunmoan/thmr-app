"""Apply compatibility fixes to resolved Android plugins, idempotently."""

import json
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


def fix_file_picker(source):
    # AGP 9 does not imply built-in Kotlin when the app explicitly opts out.
    marker = "def thmrUseLegacyKotlin ="
    if marker in source or "if (!isAgp9OrAbove)" not in source:
        return source
    lines = source.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.startswith("def isAgp9OrAbove ="):
            lines.insert(index + 1, marker + " !isAgp9OrAbove || "
                "'false'.equalsIgnoreCase(project.findProperty('android.builtInKotlin')?.toString())\n")
            return "".join(lines).replace("if (!isAgp9OrAbove)", "if (thmrUseLegacyKotlin)")
    raise ValueError("Could not locate file_picker's AGP compatibility declaration")


def main():
    root = Path(__file__).resolve().parent.parent
    config = root / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    for package in packages:
        if package["name"] not in {"flutter_inappwebview_android", "file_picker"}:
            continue
        uri = urlparse(urljoin(config.as_uri(), package["rootUri"]))
        if uri.scheme != "file" or uri.netloc:
            raise ValueError("Expected a local plugin path")
        gradle = Path(url2pathname(uri.path)) / "android/build.gradle"
        source = gradle.read_text(encoding="utf-8")
        patched = (fix_file_picker(source) if package["name"] == "file_picker" else
            source.replace("proguard-android.txt", "proguard-android-optimize.txt"))
        if patched != source:
            gradle.write_text(patched, encoding="utf-8")
        print(f"AGP compatibility checked: {gradle}")


if __name__ == "__main__":
    main()
