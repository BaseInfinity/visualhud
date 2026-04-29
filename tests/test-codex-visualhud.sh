#!/bin/bash
# Integration tests for the Codex -> VisualHUD hook adapter.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="$ROOT_DIR/.codex/hooks/visualhud-codex.sh"
HOOKS_JSON="$ROOT_DIR/.codex/hooks.json"
TMP_DIR="$(mktemp -d)"
ENGINE="$TMP_DIR/cooking-status.sh"
LOG_FILE="$TMP_DIR/events.jsonl"
OUT_FILE="$TMP_DIR/stdout.txt"
COUNTER_FILE="/private/tmp/claude-cooking-counter_w0t0p0_CODEX_TEST_SESSION"

cleanup() {
    rm -f "$COUNTER_FILE"
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$ENGINE" <<'EOF'
#!/bin/bash
INPUT=$(cat)
printf '%s' "$INPUT" | jq -c \
  --arg theme "${VISUALHUD_THEME:-}" \
  --arg default_theme "${VISUALHUD_DEFAULT_THEME:-}" \
  --arg reapply_delay "${VISUALHUD_REAPPLY_DELAY:-}" \
  '. + {visualhud_theme: $theme, visualhud_default_theme: $default_theme, visualhud_reapply_delay: $reapply_delay}' >> "$VISUALHUD_TEST_LOG"
printf 'engine stdout should not leak to Codex hook stdout\n'
EOF
chmod +x "$ENGINE"

export VISUALHUD_ENGINE="$ENGINE"
export VISUALHUD_TEST_LOG="$LOG_FILE"
export ITERM_SESSION_ID="w0t0p0:CODEX_TEST_SESSION"
unset VISUALHUD_THEME VISUALHUD_DEFAULT_THEME
rm -f "$COUNTER_FILE"

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (expected '%s', got '%s')\n" "$label" "$expected" "$actual"
    fi
}

run_adapter() {
    local payload="$1"
    printf '%s' "$payload" | bash "$ADAPTER"
}

last_event_field() {
    local jq_filter="$1"
    tail -n 1 "$LOG_FILE" | jq -r "$jq_filter"
}

echo "=== Test Suite: visualhud-codex.sh ==="
echo ""

echo "--- Test 1: PreToolUse forwards tool progress ---"
stdout="$(run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","turn_id":"turn-1","tool_name":"Bash","tool_input":{"command":"pwd"}}')"
assert_eq "Adapter keeps stdout empty for Codex hook protocol" "" "$stdout"
assert_eq "Engine receives PreToolUse" "PreToolUse" "$(last_event_field '.hook_event_name')"
assert_eq "Engine receives Codex tool name" "Bash" "$(last_event_field '.tool_name')"
assert_eq "Engine receives session id" "codex-session" "$(last_event_field '.session_id')"
assert_eq "Adapter leaves VISUALHUD_THEME open for repo-local theme file" "" "$(last_event_field '.visualhud_theme')"
assert_eq "Adapter defaults TMNT theme for Codex" "tmnt" "$(last_event_field '.visualhud_default_theme')"
assert_eq "Adapter enables delayed title/color reapply for Codex TUI" "0.12" "$(last_event_field '.visualhud_reapply_delay')"
echo ""

echo "--- Test 2: UserPromptSubmit forwards prompt reset ---"
run_adapter '{"hook_event_name":"UserPromptSubmit","session_id":"codex-session","turn_id":"turn-2","prompt":"build the adapter"}' >"$OUT_FILE"
assert_eq "Prompt reset event is forwarded" "UserPromptSubmit" "$(last_event_field '.hook_event_name')"
assert_eq "Prompt text is preserved" "build the adapter" "$(last_event_field '.prompt')"
echo ""

echo "--- Test 3: PermissionRequest maps to VisualHUD BLOCKED notification ---"
run_adapter '{"hook_event_name":"PermissionRequest","session_id":"codex-session","turn_id":"turn-3","tool_name":"Bash","tool_input":{"command":"npm install","description":"Codex wants network access"}}' >"$OUT_FILE"
assert_eq "Permission request becomes Notification" "Notification" "$(last_event_field '.hook_event_name')"
assert_eq "Permission request becomes permission_prompt" "permission_prompt" "$(last_event_field '.notification_type')"
assert_eq "Permission description is preserved" "Codex wants network access" "$(last_event_field '.message')"
assert_eq "Permission request keeps Codex default theme" "tmnt" "$(last_event_field '.visualhud_default_theme')"
echo ""

echo "--- Test 4: Stop forwards done state ---"
run_adapter '{"hook_event_name":"Stop","session_id":"codex-session","turn_id":"turn-4","last_assistant_message":"done"}' >"$OUT_FILE"
assert_eq "Stop event is forwarded" "Stop" "$(last_event_field '.hook_event_name')"
assert_eq "Stop preserves last assistant message" "done" "$(last_event_field '.last_assistant_message')"
assert_eq "Stop keeps Codex default theme" "tmnt" "$(last_event_field '.visualhud_default_theme')"
echo ""

echo "--- Test 5: TaskCompleted forwards review completion ---"
run_adapter '{"hook_event_name":"TaskCompleted","session_id":"codex-session","task":"code review finished"}' >"$OUT_FILE"
assert_eq "TaskCompleted event is forwarded" "TaskCompleted" "$(last_event_field '.hook_event_name')"
assert_eq "TaskCompleted keeps Codex default theme" "tmnt" "$(last_event_field '.visualhud_default_theme')"
echo ""

echo "--- Test 6: SessionStart initializes idle state ---"
run_adapter '{"hook_event_name":"SessionStart","session_id":"codex-session","source":"startup"}' >"$OUT_FILE"
assert_eq "SessionStart maps to done state" "Stop" "$(last_event_field '.hook_event_name')"
assert_eq "SessionStart source is preserved" "startup" "$(last_event_field '.start_source')"
assert_eq "SessionStart keeps Codex default theme" "tmnt" "$(last_event_field '.visualhud_default_theme')"
echo ""

echo "--- Test 7: Codex hooks register VisualHUD lifecycle events ---"
assert_eq "PreToolUse VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "PermissionRequest VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PermissionRequest[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "UserPromptSubmit VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.UserPromptSubmit[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "Stop VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.Stop[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "TaskCompleted VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.TaskCompleted[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "SessionStart VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.SessionStart[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
