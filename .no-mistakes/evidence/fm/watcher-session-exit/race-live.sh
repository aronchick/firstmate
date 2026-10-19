#!/usr/bin/env bash
set -eu
ROOT=$PWD
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
LAB=$(cd "$LAB" && pwd -P)
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; wait 2>/dev/null || true; rm -r "$LAB"; }
trap cleanup EXIT
alive() { local s; s=$(ps -p "$1" -o stat=) || return 1; [[ -n $s && $s != *Z* ]]; }
owner() { sleep 240 & OWNER=$!; pids+=("$OWNER"); }
start() {
 local h=$1
 [[ -f "$h/.fm-lab-home" ]] || "$ROOT/bin/fm-lab-home.sh" create "$h"
 mkdir -p "$h/state" "$h/data" "$h/config"
 echo "$OWNER" > "$h/state/.lock"
 FM_HOME="$h" FM_POLL=30 FM_CHECK_INTERVAL="${INTERVAL:-999999}" FM_HEARTBEAT=999999 "$ROOT/bin/fm-watch-arm.sh" > "$h/out" 2> "$h/err" & ARM=$!; pids+=("$ARM")
 for ((i=0;i<200;i++)); do
   if [[ -s "$h/state/.watch.lock/pid" && -f "$h/state/.last-watcher-beat" ]]; then WATCH=$(cat "$h/state/.watch.lock/pid"); pids+=("$WATCH"); alive "$WATCH" && break; fi
   sleep .1
 done
 [[ -n ${WATCH:-} ]] && alive "$WATCH" || { cat "$h/err" "$h/out"; ls -la "$h/state"; ps -p "$ARM" -o pid=,ppid=,command=; return 1; }
 echo "started home=${h##*/} owner=$OWNER arm=$ARM watcher=$WATCH"
}
gone() { for ((i=0;i<200;i++)); do alive "$1" || return 0; sleep .1; done; return 1; }
H="$LAB/race"
"$ROOT/bin/fm-lab-home.sh" create "$H"
owner; original=$OWNER
owner; replacement=$OWNER
FM_HOME="$H" bash -c '
 . "$1"
 fm_lock_acquire_wait "$STATE/.lock.acquire"
 trap '\''fm_lock_release "$STATE/.lock.acquire"'\'' EXIT
 touch "$FM_HOME/held"
 while [ ! -e "$FM_HOME/release" ]; do sleep .1; done
 echo "$2" > "$STATE/.lock"
' _ "$ROOT/bin/fm-wake-lib.sh" "$replacement" & holder=$!; pids+=("$holder")
for ((i=0;i<200;i++)); do [[ ! -f "$H/held" ]] || break; sleep .1; done
[[ -f "$H/held" ]]
OWNER=$original; start "$H"
kill "$original"; wait "$original" 2>/dev/null || true
kill -KILL "$ARM"; wait "$ARM" 2>/dev/null || true
touch "$H/release"; wait "$holder"
sleep 3; alive "$WATCH"; alive "$replacement"
echo "PASS replacement=$replacement published before first observation; watcher=$WATCH survives old owner=$original and launcher=$ARM exit"
kill "$replacement"; wait "$replacement" 2>/dev/null || true
gone "$WATCH"
cat "$H/err"
echo 'PASS replacement exit stops preserved watcher'
