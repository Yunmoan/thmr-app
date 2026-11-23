#!/bin/bash
set -euo pipefail
app=${1:-build/macos/Build/Products/Release/THMR.app}
test -d "$app/Contents"
command -v create-dmg >/dev/null
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/thmr-dmg.XXXXXX")
trap 'rm -rf "$work"' EXIT
ditto "$app" "$work/THMR.app"
# 坐标与 tool/dmg/background.png 对应。Finder 的 AppleScript 负责显示安装背景和拖拽指引，
# 超时和重试可避免偶发卡住整个发布任务。
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
