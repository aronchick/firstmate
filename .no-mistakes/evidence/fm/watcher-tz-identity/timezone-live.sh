#!/bin/bash
set -eu
ROOT=$PWD
E=/Users/daaronch/.no-mistakes/evidence/01M57YG5Y9JK5SPWNYV77H83MZ
LAB=$(mktemp -d "$PWD/.tz-lab.XXXXXX")
WP=
cleanup() { if [ -n "$WP" ]; then kill "$WP" 2>/dev/null || true; wait "$WP" 2>/dev/null || true; fi; rm -rf "$LAB"; }
trap cleanup EXIT
bin/fm-lab-home.sh create "$LAB"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE
export FM_HOME="$LAB"
export FM_POLL=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999
TZ=Pacific/Honolulu bash bin/fm-watch.sh > "$E/watcher-output.log" 2>&1 &
WP=$!
. bin/fm-wake-lib.sh
for i in {1..100}; do
 if fm_watcher_healthy "$LAB/state" "$ROOT/bin/fm-watch.sh" 300 "$LAB"; then break; fi
 sleep .1
done
fm_watcher_healthy "$LAB/state" "$ROOT/bin/fm-watch.sh" 300 "$LAB"
printf 'Darwin real watcher pid=%s recorded identity: ' "$WP"
cat "$LAB/state/.watch.lock/pid-identity"
for zone in UTC America/New_York Pacific/Honolulu Asia/Tokyo; do
 printf 'raw ps TZ=%s: ' "$zone"
 TZ="$zone" ps -p "$WP" -o lstart=
 TZ="$zone" fm_watcher_healthy "$LAB/state" "$ROOT/bin/fm-watch.sh" 300 "$LAB"
 printf 'health TZ=%s: healthy pid=%s\n' "$zone" "$FM_WATCHER_HEALTHY_PID"
done
saved=$(cat "$LAB/state/.watch.lock/pid-identity")
printf 'wrong-process-identity\n' > "$LAB/state/.watch.lock/pid-identity"
if TZ=America/New_York fm_watcher_healthy "$LAB/state" "$ROOT/bin/fm-watch.sh" 300 "$LAB"; then exit 21; fi
printf '%s\n' "$saved" > "$LAB/state/.watch.lock/pid-identity"
echo 'Mismatched live PID identity: rejected'
. bin/fm-pending-reply-lib.sh
. bin/fm-remote-job-lib.sh
p1=$(TZ=Pacific/Honolulu fm_pending_reply_pid_identity "$$")
r1=$(TZ=Pacific/Honolulu fm_remote_job_process_start "$$")
for zone in UTC America/New_York Asia/Tokyo; do
 test "$p1" = "$(TZ="$zone" fm_pending_reply_pid_identity "$$")"
 test "$r1" = "$(TZ="$zone" fm_remote_job_process_start "$$")"
 printf 'Real-process library identities TZ=%s: pending-reply and remote-job stable\n' "$zone"
done
kill "$WP"
wait "$WP" || true
if kill -0 "$WP" 2>/dev/null; then exit 22; fi
WP=
echo 'Watcher terminated and reaped; disposable home removed by EXIT trap'
