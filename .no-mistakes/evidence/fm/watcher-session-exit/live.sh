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
owner; a=$OWNER; start "$LAB/a"; aw=$WATCH
owner; b=$OWNER; start "$LAB/b"; bw=$WATCH; ba=$ARM
kill "$a"; wait "$a" 2>/dev/null || true; gone "$aw"; alive "$bw"; alive "$b"
cat "$LAB/a/err"; echo 'PASS owner exit stops watcher; second home owner and watcher survive'
sleep 2; alive "$bw"; kill -KILL "$ba"; wait "$ba" 2>/dev/null || true; gone "$bw"; alive "$b"
cat "$LAB/b/err"; echo 'PASS launcher exit stops watcher while shared owner survives'
owner; old=$OWNER; start "$LAB/replacement"; rw=$WATCH; ra=$ARM
owner; replacement=$OWNER
FM_HOME="$LAB/replacement" bash -c '. "$1"; fm_lock_acquire_wait "$STATE/.lock.acquire"; echo "$2" > "$STATE/.lock"; fm_lock_release "$STATE/.lock.acquire"' _ "$ROOT/bin/fm-wake-lib.sh" "$replacement"
kill "$old"; wait "$old" 2>/dev/null || true; sleep 2; kill -KILL "$ra"; wait "$ra" 2>/dev/null || true
for posture in away quiet; do echo "$posture" > "$LAB/replacement/state/.afk"; sleep 2; alive "$rw"; echo "replacement watcher=$rw survives posture=$posture"; done
kill "$replacement"; wait "$replacement" 2>/dev/null || true; gone "$rw"; cat "$LAB/replacement/err"
echo 'PASS replacement survives original owner and launcher exit; stops at replacement exit'
owner; blocked=$OWNER
"$ROOT/bin/fm-lab-home.sh" create "$LAB/blocked"
mkdir -p "$LAB/blocked/state" "$LAB/blocked/config" "$LAB/blocked/data"
cat > "$LAB/blocked/state/blocked.check.sh" <<'CHECK'
#!/usr/bin/env bash
echo "$$" > "$FM_HOME/check.pid"
exec sleep 240
CHECK
chmod 0700 "$LAB/blocked/state/blocked.check.sh"
FM_HOME="$LAB/blocked" "$ROOT/bin/fm-check-register.sh" blocked
INTERVAL=1 start "$LAB/blocked"; cw=$WATCH
for ((i=0;i<200;i++)); do [[ ! -s "$LAB/blocked/check.pid" ]] || break; sleep .1; done
cpid=$(cat "$LAB/blocked/check.pid"); alive "$cpid"; pids+=("$cpid")
kill "$blocked"; wait "$blocked" 2>/dev/null || true; gone "$cw"; gone "$cpid"; cat "$LAB/blocked/err"
echo "PASS owner exit stops watcher=$cw and blocked check=$cpid"
echo 'All direct process scenarios passed; cleanup follows via EXIT trap.'
