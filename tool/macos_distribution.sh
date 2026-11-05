#!/bin/bash
set -euo pipefail
app=build/macos/Build/Products/Release/THMR.app
if [ -n "${MACOS_CERTIFICATE_BASE64:-}" ]; then
keychain="$RUNNER_TEMP/thmr-signing.keychain-db"
password=$(openssl rand -hex 24)
trap 'security delete-keychain "$keychain" >/dev/null 2>&1 || true; rm -f "$RUNNER_TEMP/thmr-signing.p12" "$RUNNER_TEMP/thmr-apple-api.p8"' EXIT
python3 - <<'PY'
import base64, os
from pathlib import Path
target = Path(os.environ['RUNNER_TEMP'])
for name in ['MACOS_CODESIGN_IDENTITY', 'APPLE_API_KEY_P8', 'APPLE_API_KEY_ID', 'APPLE_API_ISSUER_ID']:
    if not os.environ.get(name):
        raise SystemExit('Missing macOS distribution secret: ' + name)
(target / 'thmr-signing.p12').write_bytes(base64.b64decode(os.environ['MACOS_CERTIFICATE_BASE64'], validate=True))
(target / 'thmr-apple-api.p8').write_text(os.environ['APPLE_API_KEY_P8'])
for name in ['thmr-signing.p12', 'thmr-apple-api.p8']:
    (target / name).chmod(0o600)
PY
security create-keychain -p "$password" "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$RUNNER_TEMP/thmr-signing.p12" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
codesign --force --deep --options runtime --timestamp --sign "$MACOS_CODESIGN_IDENTITY" \
  --keychain "$keychain" --entitlements macos/Runner/Release.entitlements "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$RUNNER_TEMP/thmr-notarize.zip"
xcrun notarytool submit "$RUNNER_TEMP/thmr-notarize.zip" --wait \
  --key "$RUNNER_TEMP/thmr-apple-api.p8" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID"
xcrun stapler staple "$app"
codesign --verify --deep --strict "$app"
else
  echo 'Developer ID not configured: macOS artifacts use local signing and are not notarized.'
fi

# Both distributions come from the same app, after signing and stapling.
ditto -c -k --sequesterRsrc --keepParent "$app" thmr-app-macos-universal.zip
bash tool/package_macos_dmg.sh "$app"
if [ -n "${MACOS_CERTIFICATE_BASE64:-}" ]; then
  codesign --force --timestamp --sign "$MACOS_CODESIGN_IDENTITY" \
    --keychain "$keychain" thmr-app-macos-universal.dmg
  xcrun notarytool submit thmr-app-macos-universal.dmg --wait \
    --key "$RUNNER_TEMP/thmr-apple-api.p8" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID"
  xcrun stapler staple thmr-app-macos-universal.dmg
  xcrun stapler validate thmr-app-macos-universal.dmg
fi
python3 tool/verify_macos_dmg.py thmr-app-macos-universal.dmg
