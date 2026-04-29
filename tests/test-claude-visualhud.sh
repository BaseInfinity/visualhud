#!/bin/bash
# Integration tests for the Claude Code -> VisualHUD hook adapter.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="$ROOT_DIR/.claude/hooks/visualhud-claude.sh"
SETTINGS_JSON="$ROOT_DIR/.claude/settings.json"
TMP_DIR="$(mktemp -d)"
ENGINE="$TMP_DIR/engine.sh"
LOG_FILE="$TMP_DIR/events.jsonl"
OUT_FILE="$TMP_DIR/stdout.txt"

cleanup() {
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
printf 'engine stdout should not leak to Claude hook stdout\n'
EOF
chmod +x "$ENGINE"

export VISUALHUD_ENGINE="$ENGINE"
export VISUALHUD_TEST_LOG="$LOG_FILE"
export ITERM_SESSION_ID="w0t0p0:CLAUDE_TEST_SESSION"
unset VISUALHUD_THEME VISUALHUD_DEFAULT_THEME

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

assert_file_exists() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$filepath" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (file does not exist: %s)\n" "$label" "$filepath"
    fi
}

run_adapter() {
    local payload="$1"
    if [ ! -f "$ADAPTER" ]; then
        printf '__missing_adapter__'
        return 0
    fi
    printf '%s' "$payload" | bash "$ADAPTER"
}

last_event_field() {
    local jq_filter="$1"
    tail -n 1 "$LOG_FILE" | jq -r "$jq_filter"
}

echo "=== Test Suite: visualhud-claude.sh ==="
echo ""

echo "--- Test 1: Claude adapter exists and forwards native events ---"
assert_file_exists "Claude VisualHUD adapter exists" "$ADAPTER"
stdout="$(run_adapter '{"hook_event_name":"PreToolUse","session_id":"claude-session","tool_name":"Read","tool_input":{"file_path":"README.md"}}')"
    assert_eq "Adapter keeps stdout empty for Claude hook UX" "" "$stdout"
if [ -f "$LOG_FILE" ]; then
    assert_eq "Engine receives Claude PreToolUse" "PreToolUse" "$(last_event_field '.hook_event_name')"
    assert_eq "Engine receives Claude tool name" "Read" "$(last_event_field '.tool_name')"
    assert_eq "Claude adapter leaves VISUALHUD_THEME open for repo-local theme file" "" "$(last_event_field '.visualhud_theme')"
    assert_eq "Claude adapter defaults to Pokemon theme" "pokemon" "$(last_event_field '.visualhud_default_theme')"
    assert_eq "Claude adapter enables delayed title/color reapply" "0.12" "$(last_event_field '.visualhud_reapply_delay')"
else
    assert_eq "Engine receives Claude PreToolUse" "PreToolUse" "__missing_log__"
    assert_eq "Engine receives Claude tool name" "Read" "__missing_log__"
    assert_eq "Claude adapter leaves VISUALHUD_THEME open for repo-local theme file" "" "__missing_log__"
    assert_eq "Claude adapter defaults to Pokemon theme" "pokemon" "__missing_log__"
    assert_eq "Claude adapter enables delayed title/color reapply" "0.12" "__missing_log__"
fi
echo ""

echo "--- Test 2: Claude adapter respects explicit theme override ---"
export VISUALHUD_THEME="tmnt"
run_adapter '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs permission","session_id":"claude-session"}' >"$OUT_FILE"
assert_eq "Claude notification is forwarded" "Notification" "$(last_event_field '.hook_event_name')"
assert_eq "Claude permission prompt is preserved" "permission_prompt" "$(last_event_field '.notification_type')"
assert_eq "Claude adapter respects VISUALHUD_THEME override" "tmnt" "$(last_event_field '.visualhud_theme')"
assert_eq "Claude adapter keeps Pokemon as default while explicit override is active" "pokemon" "$(last_event_field '.visualhud_default_theme')"
unset VISUALHUD_THEME
echo ""

echo "--- Test 3: Claude project settings register VisualHUD without removing SDLC hooks ---"
assert_eq "PreToolUse VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$SETTINGS_JSON")"
assert_eq "Notification VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.Notification[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$SETTINGS_JSON")"
assert_eq "UserPromptSubmit VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.UserPromptSubmit[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$SETTINGS_JSON")"
assert_eq "Stop VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.Stop[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$SETTINGS_JSON")"
assert_eq "StopFailure VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.StopFailure[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$SETTINGS_JSON")"
assert_eq "Existing SDLC prompt hook preserved" "true" "$(jq -r 'any(.hooks.UserPromptSubmit[]?.hooks[]?; .command | contains("sdlc-prompt-check.sh"))' "$SETTINGS_JSON")"
assert_eq "Existing TDD pretool hook preserved" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command | contains("tdd-pretool-check.sh"))' "$SETTINGS_JSON")"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
