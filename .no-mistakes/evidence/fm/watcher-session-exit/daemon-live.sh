#!/usr/bin/env bash
set -eu
ROOT=$PWD
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
LAB=$(cd "$LAB" && pwd -P)
"$ROOT/bin/fm-lab-home.sh" create "$LAB"
mkdir -p "$LAB/tmux"
export TMUX_TMPDIR="$LAB/tmux"
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; tmux -L fm-lab kill-server 2>/dev/null || true; wait 2>/dev/null || true; rm -r "$LAB"; }
trap cleanup EXIT
tmux -L fm-lab new-session -d -s supervisor -c "$ROOT" 'sleep 240'
TARGET=$(tmux -L fm-lab display-message -p -t supervisor "#{pane_id}")
export TMUX="$LAB/tmux/tmux-$(id -u)/fm-lab,0,0"
alive() { local s; s=$(ps -p "$1" -o stat=) || return 1; [[ -n $s && $s != *Z* ]]; }
nextwatch() {
 local previous=${1:-} p
 for ((i=0;i<200;i++)); do
  p=$(cat "$LAB/state/.watch.lock/pid" 2>/dev/null || true)
  if [[ -n $p && $p != "$previous" && -f "$LAB/state/.last-watcher-beat" ]] && alive "$p"; then WATCH=$p; pids+=("$p"); echo "watcher=$p previous=$previous"; return; fi
  sleep .1
 done
 cat "$LAB/state/.supervise-daemon.log" "$LAB/err"; return 1
}
sleep 240 & owner=$!; pids+=("$owner")
echo "$owner" > "$LAB/state/.lock"
echo quiet > "$LAB/state/.afk"
FM_HOME="$LAB" FM_SUPERVISOR_BACKEND=tmux FM_SUPERVISOR_TARGET="$TARGET" FM_POLL=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 FM_HOUSEKEEPING_TICK=999999 "$ROOT/bin/fm-supervise-daemon.sh" > "$LAB/out" 2> "$LAB/err" & daemon=$!; pids+=("$daemon")
nextwatch
kill "$WATCH"; nextwatch "$WATCH"
echo 'PASS daemon restarts watcher while owner lives'
sleep 240 & replacement=$!; pids+=("$replacement")
FM_HOME="$LAB" bash -c '. "$1"; fm_lock_acquire_wait "$STATE/.lock.acquire"; echo "$2" > "$STATE/.lock"; fm_lock_release "$STATE/.lock.acquire"' _ "$ROOT/bin/fm-wake-lib.sh" "$replacement"
kill "$owner"; wait "$owner" 2>/dev/null || true; sleep 2; alive "$daemon"
nextwatch; kill "$WATCH"; nextwatch "$WATCH"
echo 'PASS daemon restarts watcher for live replacement after old owner exits'
kill "$replacement"; wait "$replacement" 2>/dev/null || true
for ((i=0;i<200;i++)); do alive "$daemon" || break; sleep .1; done
! alive "$daemon"
! alive "$WATCH"
[[ ! -e "$LAB/state/.supervise-daemon.pid" && ! -e "$LAB/state/.watch.lock/pid" ]]
cat "$LAB/state/.supervise-daemon.log"
echo 'PASS replacement exit stops daemon and watcher, releases both ownership records'
