#!/bin/bash
set -eu
LAB=$(mktemp -d "$PWD/.tz-focused.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE
export FM_HOME="$LAB"
. bin/fm-wake-lib.sh
. bin/fm-pending-reply-lib.sh
. bin/fm-remote-job-lib.sh
rec="$LAB/sender"
printf 'recovery_sender_pid=%s\nrecovery_sender_identity=%s\n' "$$" "$(TZ=Pacific/Honolulu fm_pending_reply_pid_identity "$$")" > "$rec"
TZ=America/New_York fm_pending_reply_sender_alive "$rec"
echo 'Pending-reply persisted sender: alive after Honolulu -> New York'
fm_pending_reply_set "$rec" recovery_sender_identity wrong
if fm_pending_reply_sender_alive "$rec"; then exit 11; fi
echo 'Pending-reply mismatched identity: rejected'
mkdir "$LAB/owner"
printf '%s\n' "$$" > "$LAB/owner/pid"
TZ=Pacific/Honolulu fm_remote_job_process_start "$$" > "$LAB/owner/start"
fm_remote_job_process_command "$$" > "$LAB/owner/command"
TZ=America/New_York fm_remote_job_recorded_owner_alive "$LAB/owner"
echo 'Remote-job persisted owner: alive after Honolulu -> New York'
printf 'wrong\n' > "$LAB/owner/start"
if fm_remote_job_recorded_owner_alive "$LAB/owner"; then exit 12; fi
echo 'Remote-job mismatched start: rejected'
# Execute the exact base function body against real ps, without replacing source files.
eval "$(git show 45dd50a5e12bc3f5e009a4e18fa35ce7f7a71681:bin/fm-wake-lib.sh | sed -n '/^fm_pid_identity() {/,/^}/p')"
a=$(TZ=Pacific/Honolulu fm_pid_identity "$$")
b=$(TZ=America/New_York fm_pid_identity "$$")
test "$a" != "$b"
printf 'Before fix identity differs:\n%s\n%s\n' "$a" "$b"
. bin/fm-wake-lib.sh
a=$(TZ=Pacific/Honolulu fm_pid_identity "$$")
b=$(TZ=America/New_York fm_pid_identity "$$")
test "$a" = "$b"
echo 'After fix identity matches for the same real process'
eval "$(sed -n '/^fm_nm_trim() {/,/^}/p' bin/fm-nm-run-lib.sh)"
eval "$(sed -n '/^task_process_identity() {/,/^}/p; /^task_process_identity_matches() {/,/^}/p' bin/fm-teardown.sh)"
a=$(TZ=Pacific/Honolulu task_process_identity "$$")
TZ=America/New_York task_process_identity_matches "$$" "$a"
if task_process_identity_matches "$$" wrong; then exit 13; fi
printf 'Teardown identity helper: timezone match and wrong-identity rejection (%s)\n' "$a"
