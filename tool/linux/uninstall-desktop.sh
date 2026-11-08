#!/bin/sh
set -eu
data_dir=${XDG_DATA_HOME:-$HOME/.local/share}
case "$data_dir" in /*) ;; *) printf '%s\n' 'XDG_DATA_HOME 必须是绝对路径。' >&2; exit 1;; esac
entry="$data_dir/applications/cn.yunmoan.thmr.thmr_app.desktop"
if [ -e "$entry" ]; then
  grep -qx 'X-THMR-Managed=true' "$entry" || {
    printf '%s\n' '桌面入口不是由 THMR 脚本创建，不会删除。' >&2; exit 1;
  }
  rm -- "$entry"
fi
rm -f -- "$data_dir/icons/hicolor/512x512/apps/cn.yunmoan.thmr.thmr_app.png"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$data_dir/applications" >/dev/null 2>&1 || true
fi
printf '%s\n' '已移除当前用户的 THMR 菜单入口和图标；程序与用户设置保留。'
