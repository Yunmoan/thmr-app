"""Configure App Store Connect signing on a GitHub-hosted macOS runner."""

import base64
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import tempfile
import uuid


SECRET_NAMES = (
    "IOS_CERTIFICATE_BASE64",
    "IOS_CERTIFICATE_PASSWORD",
    "IOS_PROVISIONING_PROFILE_BASE64",
    "IOS_APP_STORE_CONNECT_KEY_ID",
    "IOS_APP_STORE_CONNECT_ISSUER_ID",
    "IOS_APP_STORE_CONNECT_KEY_P8",
)


def security(*args, capture=False):
    result = subprocess.run(
        ["security", *args], stdout=subprocess.PIPE if capture else subprocess.DEVNULL
    )
    if result.returncode:
        raise SystemExit(f"Apple signing setup failed during security {args[0]}")
    return result.stdout


def decode_secret(name):
    try:
        return base64.b64decode("".join(os.environ[name].split()), validate=True)
    except ValueError:
        raise SystemExit(f"Invalid Base64 in {name}") from None


def prepare_signing():
    runner_temp = Path(os.environ["RUNNER_TEMP"])
    keychain = str(runner_temp / "thmr-ios-signing.keychain-db")
    password = secrets.token_hex(24)

    with tempfile.TemporaryDirectory(dir=runner_temp) as directory:
        certificate_file = Path(directory) / "distribution.p12"
        profile_file = Path(directory) / "distribution.mobileprovision"
        certificate_file.write_bytes(decode_secret("IOS_CERTIFICATE_BASE64"))
        profile_file.write_bytes(decode_secret("IOS_PROVISIONING_PROFILE_BASE64"))
        profile = plistlib.loads(security("cms", "-D", "-i", str(profile_file), capture=True))
        entitlements = profile["Entitlements"]
        if (
            "iOS" not in profile.get("Platform", [])
            or "ProvisionedDevices" in profile
            or profile.get("ProvisionsAllDevices")
            or entitlements.get("get-task-allow")
        ):
            raise SystemExit("Use an iOS App Store Connect distribution provisioning profile")
        if profile["ExpirationDate"].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
            raise SystemExit("The iOS provisioning profile has expired")

        team_id = profile["TeamIdentifier"][0]
        bundle_id = entitlements["application-identifier"].partition(".")[2]
        if not re.fullmatch(r"[A-Z0-9]{10}", team_id) or not re.fullmatch(
            r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*", bundle_id
        ):
            raise SystemExit("Use a provisioning profile for an explicit iOS App ID")
        profile_id = str(uuid.UUID(profile["UUID"])).upper()
        certificate, = profile["DeveloperCertificates"]
        fingerprint = hashlib.sha1(certificate).hexdigest().upper()

        security("create-keychain", "-p", password, keychain)
        security("set-keychain-settings", "-lut", "3600", keychain)
        security("unlock-keychain", "-p", password, keychain)
        security("import", str(certificate_file), "-k", keychain,
                 "-P", os.environ["IOS_CERTIFICATE_PASSWORD"], "-T", "/usr/bin/codesign")
        security("set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s",
                 "-k", password, keychain)
        identities = security("find-identity", "-v", "-p", "codesigning", keychain, capture=True)
        if fingerprint.encode("ascii") not in identities:
            raise SystemExit("The P12 must contain the provisioning profile's signing identity and private key")
        security("list-keychains", "-d", "user", "-s", keychain)

        profiles = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
        profiles.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(profile_file, profiles / f"{profile_id}.mobileprovision")

    Path("ios/Flutter/TestFlightSigning.xcconfig").write_text(
        "CODE_SIGN_STYLE = Manual\n"
        f"DEVELOPMENT_TEAM = {team_id}\n"
        f"CODE_SIGN_IDENTITY[sdk=iphoneos*] = {fingerprint}\n"
        f"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*] = {profile_id}\n",
        encoding="utf-8",
    )
    (runner_temp / "ios-export-options.plist").write_bytes(plistlib.dumps({
        "method": "app-store-connect",
        "destination": "export",
        "teamID": team_id,
        "signingStyle": "manual",
        "signingCertificate": fingerprint,
        "provisioningProfiles": {bundle_id: profile_id},
        "manageAppVersionAndBuildNumber": False,
    }))
    return bundle_id


if __name__ == "__main__":
    missing = [name for name in SECRET_NAMES if not os.environ.get(name, "").strip()]
    if len(missing) == len(SECRET_NAMES):
        print("::notice::Configure the testflight environment secrets to enable iOS uploads.")
        result = "enabled=false\n"
    elif missing:
        raise SystemExit("Missing TestFlight secrets: " + ", ".join(missing))
    else:
        result = f"enabled=true\nbundle_id={prepare_signing()}\n"
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(result)
