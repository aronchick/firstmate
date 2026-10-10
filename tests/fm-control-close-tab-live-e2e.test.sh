#!/usr/bin/env bash
# Token-free native Herdr/Pi proof: close an idle worker with an unsent draft.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/herdr-test-safety.sh
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane
fm_live_gate default-on FM_HERDR_CLOSE_TAB_LIVE_E2E herdr jq pi
TMP_ROOT=$(fm_test_tmproot fm-close-tab-live)
mkdir -p "$TMP_ROOT/project" "$TMP_ROOT/pi-agent"
SESSION=$("$ROOT/bin/fm-herdr-lab.sh" name close-tab)
cleanup() {
  local rc=$?
  "$ROOT/bin/fm-herdr-lab.sh" teardown "$SESSION" || rc=1
  fm_test_cleanup
  exit "$rc"
}
trap cleanup EXIT
"$ROOT/bin/fm-herdr-lab.sh" provision "$SESSION" || fail 'lab provision failed'
lab() { "$ROOT/bin/fm-herdr-lab.sh" run "$SESSION" "$@"; }
CREATE=$(lab workspace create --cwd "$TMP_ROOT/project" --label close-tab --no-focus) \
  || fail 'workspace create failed'
PANE=$(printf '%s' "$CREATE" | jq -er '.result.root_pane.pane_id')
WS=$(printf '%s' "$CREATE" | jq -er '.result.workspace.workspace_id')
TAB=$(lab pane get "$PANE" | jq -er '.result.pane.tab_id')
cat > "$TMP_ROOT/trust.ts" <<'EOF'
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
export default function (pi: ExtensionAPI) {
  pi.on("project_trust", () => ({ trusted: "yes", remember: false }));
}
EOF
CMD=$(printf 'env PI_CODING_AGENT_DIR=%q pi -e %q --no-context-files --no-session' \
  "$TMP_ROOT/pi-agent" "$TMP_ROOT/trust.ts")
lab pane run "$PANE" "$CMD" >/dev/null || fail 'Pi launch failed'
READY=0
for _ in {1..80}; do
  STATUS=$(lab agent get "$PANE" 2>&1 | jq -r '.result.agent.agent_status // empty')
  if [ "$STATUS" = idle ]; then READY=1; break; fi
  sleep 0.25
done
[ "$READY" = 1 ] || fail 'native Pi never reached idle'
lab pane send-text "$PANE" 'unsent-guard-regression-draft' >/dev/null \
  || fail 'could not type draft without submission'
sleep 0.3
"$ROOT/bin/fm-lab-home.sh" create "$TMP_ROOT/home" >/dev/null || fail 'lab home failed'
cat > "$TMP_ROOT/home/state/worker.meta" <<EOF
window=$SESSION:$PANE
endpoint_task_id=worker
backend=herdr
herdr_session=$SESSION
herdr_workspace_id=$WS
herdr_tab_id=$TAB
herdr_pane_id=$PANE
harness=pi
kind=scout
worktree=$TMP_ROOT/project
project=$TMP_ROOT/project
EOF
OUT=$(env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE \
  -u FM_CONFIG_OVERRIDE FM_HOME="$TMP_ROOT/home" \
  bash "$ROOT/bin/fm-control.sh" worker exit --close-tab) || fail "close failed: $OUT"
assert_contains "$OUT" 'tab-closed' 'real exit command confirms closure'
SNAPSHOT=$(find "$TMP_ROOT/home/state" -name 'worker.closed-tab.*' -type f)
assert_contains "$(cat "$SNAPSHOT")" 'unsent-guard-regression-draft' 'unsent draft checkpoint'
[ -f "$TMP_ROOT/home/state/worker.meta" ] || fail 'task record removed'
[ -d "$TMP_ROOT/project" ] || fail 'worktree removed'
pass 'real idle Pi with draft closes without submission, records and worktree retained'
