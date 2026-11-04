#!/bin/sh
set -eu
old_pid=$1; target=$2; stage=$3; backup=$4; ack=$5; token=$6
executable=$7; result=$8; ready=$9; shift 9
timeout=$1; platform=$2
parent=$(CDPATH= cd -P -- "$(dirname -- "$target")" && pwd)
case "$token" in *[!a-f0-9]*|'') exit 2;; esac
[ "${#token}" -eq 64 ] || exit 2
case "$timeout" in *[!0-9]*|'') exit 2;; esac
[ "$timeout" -ge 2 ] && [ "$timeout" -le 120 ] || exit 2
case "$old_pid" in *[!0-9]*|'') exit 2;; esac
case "$executable" in thmr_app|Contents/MacOS/THMR) ;; *) exit 2;; esac
case "$stage" in "$parent"/.thmr-update-*) ;; *) exit 2;; esac
case "$backup" in "$parent"/.thmr-backup-*) ;; *) exit 2;; esac
[ "$(dirname -- "$stage")" = "$parent" ] && [ "$(dirname -- "$backup")" = "$parent" ] || exit 2
[ "$target" = "$parent/$(basename -- "$target")" ] || exit 2
[ "$target" != "$stage" ] && [ "$target" != "$backup" ] && [ "$stage" != "$backup" ] || exit 2
[ ! -L "$target" ] && [ ! -L "$stage" ] && [ ! -e "$backup" ] || exit 2
[ -f "$target/$executable" ] && [ -x "$stage/$executable" ] || exit 2
if [ "$platform" = macos ]; then /usr/bin/codesign --verify --deep --strict "$stage"; fi
moved_old=0; moved_new=0; child=''
status() { printf '{"status":"%s","message":"%s"}\n' "$1" "$2" > "$result"; }
start_app() {
  THMR_UPDATE_ACK="$ack" THMR_UPDATE_TOKEN="$token" "$target/$executable" --thmr-update-ack "$ack" --thmr-update-token "$token" </dev/null >/dev/null 2>&1 &
  child=$!
}
rollback() {
  trap - EXIT HUP INT TERM
  if [ -n "$child" ]; then
    kill "$child" 2>/dev/null || true
    sleep 2
    kill -KILL "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
  if [ "$moved_new" = 1 ] && [ -e "$target" ]; then mv -- "$target" "$stage"; fi
  if [ "$moved_old" = 1 ] && [ -d "$backup" ]; then
    mv -- "$backup" "$target"
    status rollback 'Updated application failed its startup check; previous version restored'
    "$target/$executable" </dev/null >/dev/null 2>&1 &
  else status failed 'Update could not be installed'; fi
  exit 1
}
trap rollback EXIT HUP INT TERM
printf '%s' "$token" > "$ready"
count=0
while kill -0 "$old_pid" 2>/dev/null; do
  [ ! -f "$(dirname -- "$ready")/cancel" ] || exit 1
  count=$((count+1)); [ "$count" -le 120 ] || exit 1; sleep 1
done
[ ! -f "$(dirname -- "$ready")/cancel" ] || exit 1
mv -- "$target" "$backup"; moved_old=1
mv -- "$stage" "$target"; moved_new=1
start_app
count=0
while [ "$count" -lt "$timeout" ]; do
  if [ -f "$ack" ] && [ "$(cat -- "$ack")" = "$token" ]; then
    trap - EXIT HUP INT TERM
    status success 'Update installed and application started'
    # backup was checked as a direct, non-linked sibling before any mutation.
    [ "$(dirname -- "$backup")" = "$parent" ] && [ ! -L "$backup" ] || exit 2
    rm -rf -- "$backup"
    exit 0
  fi
  count=$((count+1)); sleep 1
done
exit 1
