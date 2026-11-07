"""Sign inside-out and validate the actual macOS distribution, not just Xcode output."""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import secrets
import shutil
import subprocess
import tempfile
import time


MACHO_MAGIC = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca",
    "cafebabf", "bfbafeca",
)}
ARCHITECTURES = ("x86_64", "arm64")


def macho_files(app):
    result = []
    for path in sorted(app.rglob("*")):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as source:
            if source.read(4) in MACHO_MAGIC:
                result.append(path)
    return result


def validate_entitlements(entitlements):
    # Even an empty access-groups array is a restricted entitlement claim.
    # Ad-hoc / Developer ID builds here have no provisioning profile for it.
    for key in ("keychain-access-groups", "com.apple.application-identifier",
                "com.apple.developer.team-identifier"):
        if key in entitlements:
            raise ValueError(f"Unprovisioned entitlement: {key}")
    for key in ("com.apple.security.get-task-allow", "com.apple.security.app-sandbox"):
        if entitlements.get(key):
            raise ValueError(f"Invalid distribution entitlement: {key}")


def sign_app(app, identity="-", keychain=None):
    entitlements = Path("macos/Runner/Release.entitlements")
    validate_entitlements(plistlib.loads(entitlements.read_bytes()))
    options = ["--force", "--sign", identity]
    if identity == "-":
        options += ["--timestamp=none"]
    else:
        options += ["--options", "runtime", "--timestamp"]
    if keychain:
        options += ["--keychain", keychain]
    # Do not use --deep for signing: it propagates app entitlements into libraries.
    # Sign real files first, then their containing bundles, and the outer app last.
    for path in macho_files(app):
        if path != app / "Contents/MacOS/THMR":
            subprocess.run(["codesign", *options, str(path)], check=True)
    bundles = [p for p in app.rglob("*") if p.is_dir() and not p.is_symlink()
               and p.suffix in (".framework", ".app", ".xpc", ".appex")]
    for path in sorted(bundles, key=lambda p: (-len(p.parts), str(p))):
        subprocess.run(["codesign", *options, str(path)], check=True)
    subprocess.run(["codesign", *options, "--entitlements", str(entitlements),
                    str(app)], check=True)


def verify_app(app, launch=False):
    app = app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "cn.yunmoan.thmr.thmrApp"
    if version := os.environ.get("CLIENT_VERSION"):
        assert info["CFBundleShortVersionString"] == version.split("-")[0]
    if build := os.environ.get("CLIENT_BUILD_NUMBER"):
        assert info["CFBundleVersion"] == build
    files = macho_files(app)
    assert app / "Contents/MacOS/THMR" in files, "Missing Mach-O executable"
    for path in files:
        subprocess.run(["lipo", str(path), "-verify_arch", *ARCHITECTURES], check=True)
        subprocess.run(["codesign", "--verify", "--all-architectures", "--strict",
                        str(path)], check=True)
        for arch in ARCHITECTURES:
            result = subprocess.run(["codesign", "--display", "--arch", arch,
                                     "--entitlements", ":-", str(path)],
                                    check=True, capture_output=True)
            entitlements = plistlib.loads(result.stdout) if result.stdout.strip() else {}
            validate_entitlements(entitlements)
    subprocess.run(["codesign", "--verify", "--all-architectures", "--deep",
                    "--strict", str(app)], check=True)
    print(f"Verified universal app: {info['CFBundleShortVersionString']}+"
          f"{info['CFBundleVersion']} ({len(files)} Mach-O files)", flush=True)
    if launch:
        smoke_launch(app, info["CFBundleIdentifier"])


def smoke_launch(app, bundle_id, timeout=60):
    arch = {"x86_64": "x86_64", "arm64": "arm64"}[platform.machine()]
    token = secrets.token_hex(32)
    # Same path_provider non-sandboxed cache path used by acknowledgeInstalledUpdate.
    transaction = Path.home() / "Library/Caches" / bundle_id / "thmr-updates" / f"tx-{token}"
    transaction.mkdir(parents=True)
    ack = transaction / "ack"
    (transaction / "plan.json").write_text(json.dumps({"token": token, "target": str(app)}))
    try:
        with tempfile.TemporaryFile() as log:
            process = subprocess.Popen(["/usr/bin/arch", f"-{arch}",
                str(app / "Contents/MacOS/THMR"), "--thmr-update-ack", str(ack),
                "--thmr-update-token", token], stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError(f"{arch} app exited during startup: {process.returncode}")
                    if ack.exists() and ack.read_text() == token:
                        print(f"Native {arch} startup passed: first frame + healthy startup receipt", flush=True)
                        return
                    time.sleep(0.25)
                raise RuntimeError(f"{arch} startup did not acknowledge a healthy first frame")
            except Exception:
                log.seek(0)
                print(log.read().decode(errors="replace"), flush=True)
                raise
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    finally:
        shutil.rmtree(transaction)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("sign", "verify"))
    parser.add_argument("app", type=Path)
    parser.add_argument("--identity", default="-")
    parser.add_argument("--keychain")
    parser.add_argument("--launch", action="store_true")
    args = parser.parse_args()
    if args.action == "sign":
        sign_app(args.app, args.identity, args.keychain)
    verify_app(args.app, args.launch)
