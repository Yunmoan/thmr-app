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
# Finder's AppleScript occasionally hangs on CI runners; alarm + retry keeps
# a transient hang from blocking the whole release job.
attempt=1
until perl -e 'alarm shift; exec @ARGV' 300 create-dmg \
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
  thmr-app-macos-universal.dmg "$work"; do
  if [ "$attempt" -ge 3 ]; then
    echo 'create-dmg did not finish after retries' >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  echo "create-dmg timed out; retrying (attempt $attempt)"
  hdiutil detach '/Volumes/THMR Installer' -force 2>/dev/null || true
  rm -f thmr-app-macos-universal.dmg
done
