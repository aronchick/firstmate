#!/usr/bin/env bash
# Idle closure behavior over a canned Herdr transport and real child process.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/backends/herdr.sh"
TMP_ROOT=$(fm_test_tmproot fm-close-tab)
mkdir -p "$TMP_ROOT"
trap 'kill "${CHILD:-}" 2>/dev/null || true; rm -rf "$TMP_ROOT"' EXIT
unset HERDR_PANE_ID
STATE=live STATUS=idle SHARED=0 CLOSED=0 HARNESS=agy PROCESS_STATE=agent
sleep 120 &
CHILD=$!
fm_backend_herdr_cli() {
  shift
  case "$1 $2" in
    'pane list')
      jq -n --argjson shared "$SHARED" '{result:{panes:
        [{pane_id:"w:p",tab_id:"w:t",workspace_id:"w"}]
        + (if $shared == 1 then [{pane_id:"w:p2",tab_id:"w:t",workspace_id:"w"}] else [] end)}}'
      ;;
    'agent get')
      jq -n --arg status "$STATUS" --arg harness "$HARNESS" '{result:{agent:{pane_id:"w:p",agent:$harness,agent_status:$status}}}'
      ;;
    'pane process-info')
      jq -n --argjson pid "$CHILD" '{result:{process_info:{pane_id:"w:p",foreground_processes:[{pid:$pid}]}}}'
      ;;
    'pane get') printf '%s\n' '{"error":{"code":"pane_not_found"}}' >&2; return 1 ;;
    *) return 1 ;;
  esac
}
fm_backend_herdr_pane_agent_state() { printf '%s' "$STATE"; }
fm_backend_herdr_pane_process_state() { printf '%s' "$PROCESS_STATE"; }
fm_backend_herdr_visible_capture() { printf '> unsent draft\n'; }
fm_backend_herdr_kill() {
  [ "$1" = 'lab:w:p' ] || fail 'wrong endpoint closed'
  CLOSED=$((CLOSED + 1))
  kill "$CHILD"
  wait "$CHILD" 2>/dev/null || true
}
reject() {
  if fm_backend_herdr_close_idle_task lab:w:p w:t w "$TMP_ROOT/screen" agy; then
    fail "$1 unexpectedly closed"
  fi
  [ "$CLOSED" = 0 ] || fail "$1 mutated the endpoint"
  pass "$1 refuses without closing"
}
export HERDR_PANE_ID=w:p
reject 'supervisor pane'
unset HERDR_PANE_ID
SHARED=1
reject 'shared tab'
SHARED=0 STATUS=working
reject 'busy worker'
STATUS=idle STATE=unknown
reject 'unreadable worker'
STATE=live STATUS=idle
HARNESS=codex
reject 'replaced harness'
HARNESS=agy
PROCESS_STATE=other
reject 'registered idle with unrelated busy command'
STATE=no-agent PROCESS_STATE=other
reject 'unregistered busy command'
PROCESS_STATE=unreadable
reject 'unregistered unreadable process'
PROCESS_STATE=agent
STATE=live
fm_backend_herdr_close_idle_task lab:w:p w:t w "$TMP_ROOT/screen" agy \
  || fail 'idle close failed'
[ "$CLOSED" = 1 ] || fail 'idle close missing'
assert_contains "$(cat "$TMP_ROOT/screen")" 'unsent draft' 'visible viewport checkpoint contains draft'
kill -0 "$CHILD" 2>/dev/null && fail 'worker survived close'
pass 'idle closure captures visible draft without submission and proves process gone'
