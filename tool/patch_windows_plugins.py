"""Fix legacy plugin build scripts without pinning their package versions."""

import json
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


def fix_webview(source):
    if "TARGET ${PROJECT_NAME}_DEPENDENCIES_DOWNLOAD PRE_BUILD" in source:
        # DEPENDS is only valid with the OUTPUT form of add_custom_command.
        return source.replace("\n  DEPENDS ${NUGET}", "")
    return source


def fix_media_kit(source):
    return source.replace(
        'TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"\n    COMMAND',
        'TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT" POST_BUILD\n    COMMAND',
    )


def fix_symlinks(source):
    return source.replace(
        "$item = Get-Item $realPath",
        "$item = Get-Item -LiteralPath $realPath -Force",
    )


def main():
    config = Path(__file__).resolve().parent.parent / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    fixes = {
        "flutter_inappwebview_windows": ("windows/CMakeLists.txt", fix_webview),
        "media_kit_libs_windows_audio": ("windows/CMakeLists.txt", fix_media_kit),
        "smtc_windows": ("cargokit/cmake/resolve_symlinks.ps1", fix_symlinks),
    }
    for package in packages:
        if package["name"] not in fixes:
            continue
        uri = urlparse(urljoin(config.as_uri(), package["rootUri"]))
        if uri.scheme != "file" or uri.netloc:
            raise ValueError("Expected a local plugin directory")
        relative, transform = fixes[package["name"]]
        target = Path(url2pathname(uri.path)) / relative
        source = target.read_text(encoding="utf-8")
        patched = transform(source)
        if patched != source:
            target.write_text(patched, encoding="utf-8")
            print(f"Updated native build compatibility: {package['name']}")


if __name__ == "__main__":
    main()
