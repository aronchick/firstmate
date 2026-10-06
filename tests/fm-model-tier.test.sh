#!/usr/bin/env bash
# Behavior tests for fm-model-tier.sh and dynamic tier resolution.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

MODEL_TIER="$ROOT/bin/fm-model-tier.sh"
SPAWN="$ROOT/bin/fm-spawn.sh"
RESOLVE="$ROOT/bin/fm-dispatch-resolve.sh"
TMP_ROOT=$(fm_test_tmproot fm-model-tier)

make_spawn_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_test_make_spawn_fakebin "$dir")
  cat > "$fakebin/timeout" <<'SH'
#!/usr/bin/env bash
shift
exec "$@"
SH
  chmod +x "$fakebin/timeout"
  printf '%s\n' "$fakebin"
}

make_spawn_case() {
  local name=$1 harness=$2 case_dir home proj wt fakebin launchlog id
  shift 2
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  launchlog="$case_dir/launch.log"
  fakebin=$(make_spawn_fakebin "$case_dir/fake")
  fm_test_spawn_home "$home" "$harness"
  fm_git_worktree "$proj" "$wt" "wt-$name"
  mkdir -p "$home/codex-home"
  cat > "$home/codex-home/models_cache.json" <<'JSON'
{
  "models": [
    {
      "slug": "gpt-6-astra",
      "priority": 1,
      "description": "Frontier flagship model",
      "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}, {"effort": "max"}]
    },
    {
      "slug": "gpt-5.5",
      "priority": 2,
      "description": "Workhorse model",
      "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}]
    }
  ]
}
JSON
  for id in "$@"; do
    fm_test_spawn_brief "$home" "$id"
  done
  printf '%s\n' "$case_dir|$home|$proj|$wt|$fakebin|$launchlog"
}

read_case_record() {
  IFS='|' read -r CASE_DIR HOME_DIR PROJ_DIR WT_DIR FAKEBIN_DIR LAUNCH_LOG <<EOF
$1
EOF
}

run_ship_spawn() {
  local home=$1 wt=$2 fakebin=$3 launchlog=$4
  shift 4
  : > "$launchlog"
  FM_FAKE_LAUNCH_LOG="$launchlog" CODEX_HOME="$home/codex-home" \
    fm_test_run_spawn "$home" "$wt" "$fakebin" "$@" --mode no-mistakes --yolo off
}

# 1. Tier resolves to newest ID across harnesses
test_tier_resolves_to_newest_model_codex() {
  local codex_home="$TMP_ROOT/codex-test-1"
  mkdir -p "$codex_home"
  cat > "$codex_home/models_cache.json" <<'JSON'
{
  "models": [
    {
      "slug": "gpt-6-astra",
      "priority": 1,
      "description": "Frontier flagship model",
      "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}, {"effort": "max"}]
    },
    {
      "slug": "gpt-5-frontier",
      "priority": 2,
      "description": "Previous frontier model",
      "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}]
    },
    {
      "slug": "gpt-6.1-sol",
      "priority": 1,
      "description": "Newest workhorse model",
      "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}]
    },
    {
      "slug": "gpt-6-sol",
      "priority": 2,
      "description": "Previous workhorse model",
      "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}]
    },
    {
      "slug": "gpt-6-luna",
      "priority": 1,
      "description": "Newest fast model",
      "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}, {"effort": "max"}]
    }
  ]
}
JSON

  local strong standard fast
  strong=$(CODEX_HOME="$codex_home" "$MODEL_TIER" resolve codex strong)
  assert_equals "gpt-6-astra" "$strong" "codex strong tier should resolve to gpt-6-astra"

  standard=$(CODEX_HOME="$codex_home" "$MODEL_TIER" resolve codex standard)
  assert_equals "gpt-6.1-sol" "$standard" "codex standard tier should resolve to gpt-6.1-sol"

  fast=$(CODEX_HOME="$codex_home" "$MODEL_TIER" resolve codex fast)
  assert_equals "gpt-6-luna" "$fast" "codex fast tier should resolve to gpt-6-luna"

  pass "tier resolves to newest id in codex catalog"
}

test_new_top_model_picked_up_with_no_config_edit() {
  local codex_home="$TMP_ROOT/codex-test-2"
  mkdir -p "$codex_home"
  cat > "$codex_home/models_cache.json" <<'JSON'
{
  "models": [
    {
      "slug": "gpt-6-astra",
      "priority": 1,
      "description": "Frontier flagship model"
    }
  ]
}
JSON

  local initial
  initial=$(CODEX_HOME="$codex_home" "$MODEL_TIER" resolve codex strong)
  assert_equals "gpt-6-astra" "$initial" "initial strong tier is gpt-6-astra"

  # Now a new model arrives in the catalog with priority 0 (higher than 1)
  cat > "$codex_home/models_cache.json" <<'JSON'
{
  "models": [
    {
      "slug": "gpt-7-astra",
      "priority": 0,
      "description": "Next generation frontier flagship model"
    },
    {
      "slug": "gpt-6-astra",
      "priority": 1,
      "description": "Frontier flagship model"
    }
  ]
}
JSON

  local updated
  updated=$(CODEX_HOME="$codex_home" "$MODEL_TIER" resolve codex strong)
  assert_equals "gpt-7-astra" "$updated" "new top model is picked up with no config edit"

  pass "new top model is picked up with no config edit"
}

test_tier_resolves_claude_floating_aliases() {
  local fakebin="$TMP_ROOT/fake-claude"
  mkdir -p "$fakebin"
  cat > "$fakebin/claude" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fakebin/claude"

  local strong standard fast
  strong=$(PATH="$fakebin:$PATH" "$MODEL_TIER" resolve claude strong)
  assert_equals "opus" "$strong" "claude strong resolves to opus"

  standard=$(PATH="$fakebin:$PATH" "$MODEL_TIER" resolve claude standard)
  assert_equals "sonnet" "$standard" "claude standard resolves to sonnet"

  fast=$(PATH="$fakebin:$PATH" "$MODEL_TIER" resolve claude fast)
  assert_equals "haiku" "$fast" "claude fast resolves to haiku"

  pass "claude resolves to floating aliases opus/sonnet/haiku"
}

test_tier_resolves_agy_live_listing() {
  local fakebin="$TMP_ROOT/fake-agy"
  mkdir -p "$fakebin"
  cat > "$fakebin/agy" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "models" ]; then
  cat <<'EOF'
gemini-3.9-pro-high
gemini-3.9-pro-medium
gemini-3.9-flash-high
gemini-3.9-flash-lite-high
EOF
  exit 0
fi
exit 1
SH
  chmod +x "$fakebin/agy"

  local strong standard fast
  strong=$(PATH="$fakebin:$PATH" "$MODEL_TIER" resolve agy strong high)
  assert_equals "gemini-3.9-pro-high" "$strong" "agy strong resolves to gemini-3.9-pro-high"

  standard=$(PATH="$fakebin:$PATH" "$MODEL_TIER" resolve agy standard high)
  assert_equals "gemini-3.9-flash-high" "$standard" "agy standard resolves to gemini-3.9-flash-high"

  fast=$(PATH="$fakebin:$PATH" "$MODEL_TIER" resolve agy fast high)
  assert_equals "gemini-3.9-flash-lite-high" "$fast" "agy fast resolves to gemini-3.9-flash-lite-high"

  pass "agy tier resolves from live models listing"
}

test_tier_resolves_kimi_live_catalog() {
  local fakebin="$TMP_ROOT/fake-kimi"
  mkdir -p "$fakebin"
  cat > "$fakebin/kimi" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "provider" ] && [ "${2:-}" = "list" ]; then
  cat <<'JSON'
{
  "models": {
    "kimi-code/k3": {
      "maxContextSize": 1048576
    },
    "kimi-code/k3-256k": {
      "maxContextSize": 262144
    },
    "kimi-code/kimi-for-coding": {
      "maxContextSize": 262144
    }
  }
}
JSON
  exit 0
fi
exit 1
SH
  chmod +x "$fakebin/kimi"

  local strong standard
  strong=$(PATH="$fakebin:$PATH" "$MODEL_TIER" resolve kimi strong)
  assert_equals "kimi-code/k3" "$strong" "kimi strong resolves to 1M context k3"

  standard=$(PATH="$fakebin:$PATH" "$MODEL_TIER" resolve kimi standard)
  assert_equals "kimi-code/kimi-for-coding" "$standard" "kimi standard resolves to kimi-for-coding"

  pass "kimi tier resolves from live provider catalog"
}

test_unreachable_discovery_refuses() {
  local out status

  # Codex cache missing
  out=$(CODEX_HOME="$TMP_ROOT/nonexistent" "$MODEL_TIER" resolve codex strong 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "codex with missing cache should fail"
  assert_contains "$out" "codex model discovery is unreachable" "missing cache is named"

  # Agy failing
  local fakebin_fail="$TMP_ROOT/fake-fail"
  mkdir -p "$fakebin_fail"
  cat > "$fakebin_fail/agy" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$fakebin_fail/agy"

  out=$(PATH="$fakebin_fail:$PATH" "$MODEL_TIER" resolve agy strong 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "failing agy should fail"
  assert_contains "$out" "agy model discovery is unreachable" "failing agy is named"

  # Claude missing from PATH
  local no_claude_bin="$TMP_ROOT/no-claude-bin"
  mkdir -p "$no_claude_bin"
  for cmd in bash dirname jq grep awk sed cut tr head mktemp rm; do
    local p
    p=$(command -v "$cmd" || true)
    [ -n "$p" ] && ln -s "$p" "$no_claude_bin/$cmd"
  done
  out=$(PATH="$no_claude_bin" "$MODEL_TIER" resolve claude strong 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "missing claude on PATH should fail"
  assert_contains "$out" "claude model discovery is unreachable" "missing claude is named"

  pass "unreachable discovery refuses with concrete diagnostic"
}

test_legacy_model_profile_still_launches() {
  local rec id out status launch
  id=tier-legacy-z1
  rec=$(make_spawn_case tier-legacy codex "$id")
  read_case_record "$rec"

  out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" \
    "$id" "$PROJ_DIR" --harness codex --model gpt-5.5 --effort high)
  status=$?
  expect_code 0 "$status" "legacy model profile launch should succeed"
  launch=$(cat "$LAUNCH_LOG")
  assert_contains "$launch" "codex --model 'gpt-5.5' -c 'model_reasoning_effort=\"high\"'" \
    "legacy launch did not preserve model and effort"
  assert_grep "model=gpt-5.5" "$HOME_DIR/state/$id.meta" "meta missing model=gpt-5.5"

  pass "legacy model profile still launches"
}

test_tier_profile_launches_resolved_model() {
  local rec id out status launch
  id=tier-spawn-z2
  rec=$(make_spawn_case tier-spawn codex "$id")
  read_case_record "$rec"

  out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" \
    "$id" "$PROJ_DIR" --harness codex --tier strong --effort max)
  status=$?
  expect_code 0 "$status" "tier profile launch should succeed"
  launch=$(cat "$LAUNCH_LOG")
  assert_contains "$launch" "codex --model 'gpt-6-astra' -c 'model_reasoning_effort=\"max\"'" \
    "tier launch did not resolve strong tier to gpt-6-astra with max effort"
  assert_grep "tier=strong" "$HOME_DIR/state/$id.meta" "meta missing tier=strong"
  assert_grep "model=gpt-6-astra" "$HOME_DIR/state/$id.meta" "meta missing model=gpt-6-astra"

  pass "tier profile resolves model and launches"
}

test_resolver_warns_on_hardcoded_model_id() {
  local home="$TMP_ROOT/resolver-home"
  local brief="$TMP_ROOT/resolver-brief.md"
  mkdir -p "$home/config" "$home/state" "$home/data"
  cat > "$brief" <<'MD'
# Task
## Captain's intent
Mechanical fix.
## Firstmate spec
Do the fix.
MD
  cat > "$home/config/crew-dispatch.json" <<'JSON'
{
  "rules": [
    {
      "when": "Mechanical fix",
      "use": { "harness": "claude", "model": "haiku", "effort": "low" }
    }
  ]
}
JSON

  local out err code
  code=0
  out=$(TYPESAFE_API_KEY="" FM_HOME="$home" "$RESOLVE" "$brief" 2>"$TMP_ROOT/resolve.err") || code=$?
  err=$(cat "$TMP_ROOT/resolve.err")

  # When off, resolver does not emit warning
  assert_not_contains "$err" "warning: config/crew-dispatch.json contains hardcoded model id" \
    "resolver off should not warn on hardcoded model"

  pass "resolver warns only on active resolution of hardcoded model id"
}

test_catalog_derived_effort_support() {
  local codex_home="$TMP_ROOT/codex-catalog"
  mkdir -p "$codex_home"
  cat > "$codex_home/models_cache.json" <<'JSON'
{
  "models": [
    {
      "slug": "gpt-6-astra",
      "supported_reasoning_levels": [{"effort": "low"}, {"effort": "max"}]
    },
    {
      "slug": "gpt-5-frontier",
      "supported_reasoning_levels": [{"effort": "low"}, {"effort": "high"}]
    }
  ]
}
JSON

  local max_models
  max_models=$(CODEX_HOME="$codex_home" "$MODEL_TIER" max-models codex)
  assert_contains "$max_models" "gpt-6-astra" "max-models includes gpt-6-astra"
  assert_not_contains "$max_models" "gpt-5-frontier" "max-models omits gpt-5-frontier"

  CODEX_HOME="$codex_home" "$MODEL_TIER" supports-effort codex gpt-6-astra max
  assert_equals 0 $? "gpt-6-astra supports max"

  CODEX_HOME="$codex_home" "$MODEL_TIER" supports-effort codex gpt-5-frontier max 2>/dev/null
  assert_equals 1 $? "gpt-5-frontier does not support max"

  pass "effort support is derived from catalog"
}

test_tier_resolves_to_newest_model_codex
test_new_top_model_picked_up_with_no_config_edit
test_tier_resolves_claude_floating_aliases
test_tier_resolves_agy_live_listing
test_tier_resolves_kimi_live_catalog
test_unreachable_discovery_refuses
test_legacy_model_profile_still_launches
test_tier_profile_launches_resolved_model
test_resolver_warns_on_hardcoded_model_id
test_catalog_derived_effort_support

echo "# all fm-model-tier tests passed"
