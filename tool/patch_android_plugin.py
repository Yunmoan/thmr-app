"""Apply the AGP compatibility fix to the resolved plugin, idempotently."""

import json
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname

root = Path(__file__).resolve().parent.parent
config = root / ".dart_tool/package_config.json"
packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
plugin = next(p for p in packages if p["name"] == "flutter_inappwebview_android")
uri = urlparse(urljoin(config.as_uri(), plugin["rootUri"]))
if uri.scheme != "file":
    raise ValueError("Expected a local plugin path")
gradle = Path(url2pathname(uri.path)) / "android/build.gradle"
source = gradle.read_text(encoding="utf-8")
patched = source.replace("proguard-android.txt", "proguard-android-optimize.txt")
if patched != source:
    gradle.write_text(patched, encoding="utf-8")
print(f"AGP compatibility checked: {gradle}")
