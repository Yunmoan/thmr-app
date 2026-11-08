#!/bin/bash
set -euo pipefail
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
data_dir=${XDG_DATA_HOME:-$HOME/.local/share}
case "$data_dir" in /*) ;; *) printf '%s\n' 'XDG_DATA_HOME 必须是绝对路径。' >&2; exit 1;; esac
case "$app_dir" in *$'\n'*|*$'\r'*|*$'\t'*) printf '%s\n' '安装路径不能包含控制字符。' >&2; exit 1;; esac
[ -x "$app_dir/thmr" ] && [ -f "$app_dir/data/flutter_assets/assets/icons/icon-512.png" ] || {
  printf '%s\n' '请从完整的 THMR bundle 目录运行此脚本。' >&2; exit 1;
}
# Escape both the Exec argument syntax and the desktop-entry string layer.
quoted=${app_dir//\\/\\\\}
quoted=${quoted//\"/\\\"}
quoted=${quoted//\$/\\\$}
quoted=${quoted//\`/\\\`}
quoted=${quoted//%/%%}
quoted=${quoted//\\/\\\\}
applications="$data_dir/applications"
icons="$data_dir/icons/hicolor/512x512/apps"
mkdir -p -- "$applications" "$icons"
entry="$applications/cn.yunmoan.thmr.thmr_app.desktop"
if [ -e "$entry" ] && ! grep -qx 'X-THMR-Managed=true' "$entry"; then
  printf '%s\n' '已有同名桌面入口，不会覆盖；请先手动检查。' >&2; exit 1
fi
temporary=$(mktemp "$applications/.thmr-desktop.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
cat > "$temporary" <<ENTRY
[Desktop Entry]
Type=Application
Name=THMR
Name[zh_CN]=东方音乐电台 THMR
Comment=TouHou Music Radio
Exec=/bin/sh "$quoted/thmr"
Icon=cn.yunmoan.thmr.thmr_app
Terminal=false
Categories=AudioVideo;Audio;Music;
StartupNotify=true
StartupWMClass=cn.yunmoan.thmr.thmr_app
X-THMR-Managed=true
ENTRY
chmod 644 "$temporary"
cp -- "$app_dir/data/flutter_assets/assets/icons/icon-512.png" "$icons/cn.yunmoan.thmr.thmr_app.png"
mv -- "$temporary" "$entry"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$applications" >/dev/null 2>&1 || true
fi
printf '%s\n' "已安装当前用户的应用菜单入口：$entry" '移动 bundle 后请重新运行此脚本；无需 sudo。'
