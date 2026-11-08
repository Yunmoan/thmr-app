#!/bin/sh
set -eu
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
export LD_LIBRARY_PATH="$app_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fail() {
  printf '%s\n' "$1" >&2
  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    if command -v zenity >/dev/null 2>&1; then
      zenity --error --title='THMR 启动失败' --text="$1" 2>/dev/null || true
    elif command -v kdialog >/dev/null 2>&1; then
      kdialog --error "$1" --title 'THMR 启动失败' 2>/dev/null || true
    fi
  fi
  exit 1
}
[ -x "$app_dir/thmr_app" ] && [ -x "$app_dir/thmr_runtime_check" ] ||
  fail 'THMR 安装包不完整，请重新解压整个 bundle 目录。'
if command -v ldd >/dev/null 2>&1; then
  for library in "$app_dir/thmr_app" "$app_dir"/lib/*.so; do
    [ -f "$library" ] || continue
    dependencies=$(ldd "$library" 2>&1) ||
      fail "无法检查 THMR 运行库，请核对系统架构和安装目录。
$dependencies"
    case "$dependencies" in
      *'not found'*) fail "THMR 缺少系统运行库，请参照 README-Linux.md 安装。
$dependencies" ;;
    esac
  done
fi
if ! message=$("$app_dir/thmr_runtime_check" 2>&1); then
  fail "$message"
fi
[ "${1:-}" != '--check-runtime' ] || exit 0
cd -- "$app_dir"
exec "$app_dir/thmr_app" "$@"
