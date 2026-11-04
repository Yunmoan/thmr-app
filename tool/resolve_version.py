"""Resolve one version/build number for all clients, without changing servers.

Priority: v* release tag > manual workflow input > pubspec.yaml.
"""

import os
from pathlib import Path
import re

SEMVER = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?"
)


def resolve_version(pubspec, env):
    match = re.search(r"^version:\s*[\"']?([^\s\"'#]+)", pubspec, re.MULTILINE)
    if not match:
        raise ValueError("pubspec.yaml is missing version")
    local_version, _, local_build = match.group(1).partition("+")
    requested = env.get("REQUESTED_VERSION", "").strip()
    if env.get("GITHUB_REF_TYPE") == "tag":
        tag = env.get("GITHUB_REF_NAME", "")
        if not tag.startswith("v"):
            raise ValueError("Release tags must start with v")
        version = tag[1:]
        if requested and requested.removeprefix("v") != version:
            raise ValueError("Manual version must match the release tag")
    else:
        version = requested.removeprefix("v") or local_version
    if not SEMVER.fullmatch(version):
        raise ValueError(f"Invalid client version: {version!r}")
    if env.get("GITHUB_RUN_NUMBER"):
        build_number = str(int(env["GITHUB_RUN_NUMBER"]) * 100 + int(env.get("GITHUB_RUN_ATTEMPT", "1")))
    else:
        build_number = local_build or "1"
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise ValueError("Build number must be a positive integer")
    return version, build_number


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    version, build_number = resolve_version(
        (root / "pubspec.yaml").read_text(encoding="utf-8"), os.environ
    )
    values = (f"version={version}\nbuild_number={build_number}\n"
              f"macos_version={version.split('-')[0]}\n")
    print(values, end="")
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a", encoding="utf-8") as target:
            target.write(values)
