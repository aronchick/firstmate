#!/usr/bin/env bash
set -eu
E=/Users/daaronch/.no-mistakes/evidence/01M58NXG5W13QAX1MXT6X6M3BY
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
LAB=$(cd "$LAB" && pwd -P)
bin/fm-lab-home.sh create "$LAB"
other=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
other=$(cd "$other" && pwd -P)
bin/fm-lab-home.sh create "$other"
pids=()
cleanup() {
 for p in "${pids[@]}"; do kill -TERM "$p" 2>/dev/null || true; done
 for h in "$LAB" "$other"; do FM_HOME="$h" bin/fm-watch-arm.sh --stop >/dev/null 2>&1 || true; done
 printf '%s\n' "$LAB" "$other" > "$E/replacement-lab-paths.txt"
}
trap cleanup EXIT
alive() { local s; s=$(ps -o stat= -p "$1") || return 1; [[ -n "$s" && "$s" != *Z* ]]; }
waitwatch() {
 for ((i=0;i<200;i++)); do
  if [[ -s "$1/state/.watch.lock/pid" && -f "$1/state/.last-watcher-beat" ]]; then W=$(cat "$1/state/.watch.lock/pid"); alive "$W" && return; fi
  sleep .1
 done
 return 1
}
gone() { for ((i=0;i<200;i++)); do alive "$1" || return 0; sleep .1; done; return 1; }
sleep 120 & owner=$!; pids+=("$owner")
sleep 120 & otherowner=$!; pids+=("$otherowner")
printf '%s\n' "$owner" > "$LAB/state/.lock"
printf '%s\n' "$otherowner" > "$other/state/.lock"
FM_HOME="$LAB" FM_POLL=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 bin/fm-watch-arm.sh > "$E/replacement-arm.log" 2>&1 & arm=$!; pids+=("$arm")
FM_HOME="$other" FM_POLL=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 bin/fm-watch-arm.sh > "$E/launcher-arm.log" 2>&1 & pids+=("$!")
waitwatch "$LAB"; watcher=$W
waitwatch "$other"; otherwatcher=$W

sleep 120 & replacement=$!; pids+=("$replacement")
FM_HOME="$LAB" bash -c '. bin/fm-wake-lib.sh; fm_lock_acquire_wait "$STATE/.lock.acquire"; printf "%s\n" "$1" > "$STATE/.lock"; fm_lock_release "$STATE/.lock.acquire"' _ "$replacement"
sleep 2
kill -TERM "$owner"
kill -KILL "$arm"
sleep 2
alive "$watcher"; alive "$replacement"; alive "$otherwatcher"
printf 'Replacement=%s preserves watcher=%s after original owner=%s and launcher=%s exit\n' "$replacement" "$watcher" "$owner" "$arm"
kill -TERM "$replacement"; gone "$watcher"
printf 'Replacement exit stops watcher=%s; other watcher remains live\n' "$watcher"
alive "$otherwatcher"
otherarm=$(ps -o ppid= -p "$otherwatcher" | tr -d ' ')
kill -KILL "$otherarm"; gone "$otherwatcher"; alive "$otherowner"
printf 'Launcher=%s exit stops watcher=%s while shared owner=%s remains live\n' "$otherarm" "$otherwatcher" "$otherowner"
cat "$E/replacement-arm.log" "$E/launcher-arm.log"
