#!/bin/bash
# Integration tests for the repo-local VisualHUD CLI.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/visualhud"
ENGINE="$ROOT_DIR/engine.sh"
PASS=0
FAIL=0
TOTAL=0
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-cli.XXXXXX")"
STATE_ROOT="$TMP_ROOT/state"
mkdir -p "$STATE_ROOT"
export VISUALHUD_STATE_DIR="$STATE_ROOT"

TEST_SESSION="w0t0p0:VISUALHUD_CLI_$(date +%s)"
export ITERM_SESSION_ID="$TEST_SESSION"
SESSION_KEY=$(printf '%s' "$TEST_SESSION" | tr ':/' '__')
COUNTER_FILE="$STATE_ROOT/claude-cooking-counter_${SESSION_KEY}"
STAGE_FILE="$STATE_ROOT/claude-cooking-stage_${SESSION_KEY}"
ATTENTION_FILE="$STATE_ROOT/claude-cooking-attention_${SESSION_KEY}"
CONTEXT_FILE="$STATE_ROOT/claude-cooking-context_${SESSION_KEY}"

cleanup() {
    rm -f "$COUNTER_FILE" "$STAGE_FILE" "$ATTENTION_FILE" "$CONTEXT_FILE" 2>/dev/null
    rm -rf "$TMP_ROOT"
    unset VISUALHUD_ROOT VISUALHUD_THEMES_DIR VISUALHUD_THEME_FILE VISUALHUD_THEME
    unset VISUALHUD_DEFAULT_THEME VISUALHUD_TTY VISUALHUD_SET_BG VISUALHUD_STATE_DIR
}
trap cleanup EXIT

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

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (expected output to contain '%s')\n" "$label" "$needle"
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
        printf "  FAIL: %s (missing file: %s)\n" "$label" "$filepath"
    fi
}

run_hook() {
    local json="$1"
    printf '%s\n' "$json" | bash "$ENGINE" >/dev/null 2>/dev/null || true
}

mkdir -p "$TMP_ROOT/themes/pokemon" "$TMP_ROOT/themes/tmnt"
cp "$ROOT_DIR/themes/pokemon/theme.json" "$TMP_ROOT/themes/pokemon/theme.json"
cp "$ROOT_DIR/themes/tmnt/theme.json" "$TMP_ROOT/themes/tmnt/theme.json"

export VISUALHUD_ROOT="$TMP_ROOT"
export VISUALHUD_THEMES_DIR="$TMP_ROOT/themes"
export VISUALHUD_THEME_FILE="$TMP_ROOT/theme"
export VISUALHUD_TTY="$TMP_ROOT/tty.log"
export VISUALHUD_SET_BG="$TMP_ROOT/set-bg.py"

cat > "$VISUALHUD_SET_BG" <<'PY'
#!/usr/bin/env python3
import sys
from pathlib import Path

Path(sys.argv[1] if len(sys.argv) > 1 else "").touch(exist_ok=True) if len(sys.argv) > 1 and sys.argv[1] else None
PY
chmod +x "$VISUALHUD_SET_BG"

echo "=== Test Suite: visualhud CLI ==="
echo ""

echo "--- Test 1: Help exits cleanly for consumer CLI discovery ---"
set +e
help_output=$("$CLI" --help 2>&1)
help_status=$?
set -e
assert_eq "Help exits zero" "0" "$help_status"
assert_contains "Help shows bare npx install command" "npx -y visualhud@latest" "$help_output"
assert_contains "Help shows Codex start command" "codex --full-auto" "$help_output"
echo ""

echo "--- Test 2: Theme CLI lists, sets, and reports repo-local theme ---"
assert_file_exists "VisualHUD CLI exists" "$CLI"
list_output=$("$CLI" theme list 2>&1 || true)
assert_contains "Theme list includes pokemon" "pokemon" "$list_output"
assert_contains "Theme list includes tmnt" "tmnt" "$list_output"
current_output=$("$CLI" theme current 2>&1 || true)
assert_eq "Theme current falls back to pokemon" "pokemon" "$current_output"
set_output=$("$CLI" theme set tmnt 2>&1 || true)
assert_eq "Theme set writes confirmation" "Active theme: tmnt" "$set_output"
assert_eq "Theme file stores selected theme" "tmnt" "$(cat "$VISUALHUD_THEME_FILE" 2>/dev/null)"
assert_eq "Theme current reads selected theme" "tmnt" "$("$CLI" theme current 2>/dev/null || true)"
echo ""

echo "--- Test 3: Invalid theme names are rejected without changing active theme ---"
invalid_output=$("$CLI" theme set missingno 2>&1 >/dev/null || true)
assert_contains "Invalid theme reports available-themes hint" "Unknown theme: missingno" "$invalid_output"
assert_eq "Invalid theme leaves active theme unchanged" "tmnt" "$(cat "$VISUALHUD_THEME_FILE" 2>/dev/null)"
echo ""

echo "--- Test 4: Active theme file hot-swaps on the next hook ---"
cleanup_stage() {
    rm -f "$COUNTER_FILE" "$STAGE_FILE" "$ATTENTION_FILE" "$CONTEXT_FILE" 2>/dev/null
    : > "$VISUALHUD_TTY"
}

cleanup_stage
unset VISUALHUD_THEME
export VISUALHUD_DEFAULT_THEME="tmnt"
rm -f "$VISUALHUD_THEME_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Adapter default theme can drive engine without forcing VISUALHUD_THEME" "tmnt-leonardo" "$(cat "$STAGE_FILE" 2>/dev/null)"

cleanup_stage
printf 'pokemon\n' > "$VISUALHUD_THEME_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Active theme file overrides adapter default on next hook" "charmander" "$(cat "$STAGE_FILE" 2>/dev/null)"

cleanup_stage
printf 'tmnt\n' > "$VISUALHUD_THEME_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Changing active theme file switches back on next hook" "tmnt-leonardo" "$(cat "$STAGE_FILE" 2>/dev/null)"

cleanup_stage
export VISUALHUD_THEME="pokemon"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Explicit VISUALHUD_THEME env still has highest priority" "charmander" "$(cat "$STAGE_FILE" 2>/dev/null)"
echo ""

cleanup

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
