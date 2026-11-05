#!/bin/bash
set -euo pipefail
app=${1:-build/macos/Build/Products/Release/THMR.app}
test -d "$app/Contents"
command -v create-dmg >/dev/null
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/thmr-dmg.XXXXXX")
trap 'rm -rf "$work"' EXIT
ditto "$app" "$work/THMR.app"
# Coordinates match tool/dmg/background.png. Keep Finder customization enabled:
# skipping AppleScript would remove the background and installation guidance.
create-dmg \
  --volname 'THMR Installer' \
  --background tool/dmg/background.png \
  --window-pos 180 120 \
  --window-size 720 500 \
  --icon-size 104 \
  --text-size 14 \
  --icon 'THMR.app' 180 220 \
  --hide-extension 'THMR.app' \
  --app-drop-link 540 220 \
  --no-internet-enable \
  thmr-app-macos-universal.dmg "$work"
