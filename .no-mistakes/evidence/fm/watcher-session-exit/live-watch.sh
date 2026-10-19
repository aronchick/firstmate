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
 printf '%s\n' "$LAB" "$other" > "$E/manual-lab-paths.txt"
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
FM_HOME="$LAB" FM_POLL=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 bin/fm-watch-arm.sh > "$E/live-arm.log" 2>&1 & arm=$!; pids+=("$arm")
FM_HOME="$other" FM_POLL=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 bin/fm-watch-arm.sh > "$E/other-arm.log" 2>&1 & pids+=("$!")
waitwatch "$LAB"; watcher=$W
waitwatch "$other"; otherwatcher=$W
printf 'Before exit: owner=%s watcher=%s other-owner=%s other-watcher=%s all alive\n' "$owner" "$watcher" "$otherowner" "$otherwatcher"
kill -TERM "$owner"; wait "$owner" 2>/dev/null || true
gone "$watcher"; alive "$otherowner"; alive "$otherwatcher"
printf 'After owner exit: watcher=%s stopped; other-owner=%s and other-watcher=%s remain alive\n' "$watcher" "$otherowner" "$otherwatcher"
cat "$E/live-arm.log"
