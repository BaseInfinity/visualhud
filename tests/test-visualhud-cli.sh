#!/bin/bash
# Integration tests for the repo-local VisualHUD CLI.

set -euo pipefail

export LC_ALL=C
export LANG=C

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
PROJECT_CHECKSUM=$(printf '%s' "$ROOT_DIR" | cksum)
PROJECT_KEY=${PROJECT_CHECKSUM%% *}
COUNTER_FILE="$STATE_ROOT/claude-cooking-counter_${SESSION_KEY}"
STAGE_FILE="$STATE_ROOT/claude-cooking-stage_${SESSION_KEY}"
ATTENTION_FILE="$STATE_ROOT/claude-cooking-attention_${SESSION_KEY}"
CONTEXT_FILE="$STATE_ROOT/claude-cooking-context_${SESSION_KEY}"
JOURNEY_FILE="$STATE_ROOT/visualhud-journey_${SESSION_KEY}_${PROJECT_KEY}.json"

cleanup() {
    rm -f "$COUNTER_FILE" "$STAGE_FILE" "$ATTENTION_FILE" "$CONTEXT_FILE" 2>/dev/null
    rm -rf "$TMP_ROOT"
    unset VISUALHUD_ROOT VISUALHUD_ENGINE VISUALHUD_THEMES_DIR VISUALHUD_THEME_FILE VISUALHUD_THEME
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

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (expected output not to contain '%s')\n" "$label" "$needle"
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
export VISUALHUD_ENGINE="$ENGINE"
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
assert_contains "Help shows Codex start command" "codex --yolo" "$help_output"
assert_contains "Help exposes explicit release journey evidence" "journey set <checkpoint> <outcome>" "$help_output"
assert_not_contains "Help does not recommend legacy full-auto flag" "codex --full-auto" "$help_output"
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
legend_output=$("$CLI" theme legend pokemon 2>&1 || true)
assert_contains "Theme legend labels indeterminate work" "WORKING" "$legend_output"
assert_contains "Theme legend labels neutral permission checks" "CHECK" "$legend_output"
assert_contains "Theme legend labels human approval explicitly" "HITL" "$legend_output"
assert_contains "Theme legend includes review" "REVIEW" "$legend_output"
assert_contains "Theme legend includes error" "ERROR" "$legend_output"
assert_contains "Theme legend includes done" "DONE" "$legend_output"
assert_contains "Theme legend includes idle" "IDLE" "$legend_output"
journey_legend_output=$(VISUALHUD_JOURNEY_PROFILE=sdlc "$CLI" theme legend pokemon 2>&1 || true)
assert_contains "Theme legend names the selected journey profile" "Journey profile: sdlc" "$journey_legend_output"
assert_contains "Theme legend maps explicit checkpoints" "CHECKPOINT" "$journey_legend_output"
assert_contains "Theme legend explains state-preserving overlays" "OVERLAY" "$journey_legend_output"
assert_contains "Theme legend explains backward movement" "ROLLBACK" "$journey_legend_output"
echo ""

echo "--- Test 2b: Journey CLI can advance explicit release-only gates ---"
export VISUALHUD_JOURNEY_PROFILE=release
"$CLI" journey set proof passed >/dev/null
assert_eq "Passing local proof enters the CI gate" "ci" \
    "$(jq -r '.current' "$JOURNEY_FILE")"
"$CLI" journey set ci passed >/dev/null
assert_eq "Passing CI enters publish" "publish" \
    "$(jq -r '.current' "$JOURNEY_FILE")"
"$CLI" journey set publish passed >/dev/null
assert_eq "Passing publish enters smoke verification" "smoke" \
    "$(jq -r '.current' "$JOURNEY_FILE")"
"$CLI" journey set smoke passed >/dev/null
assert_eq "Passing smoke completes the release journey" "done" \
    "$(jq -r '.current' "$JOURNEY_FILE")"
unset VISUALHUD_JOURNEY_PROFILE
node "$ROOT_DIR/scripts/visualhud-json.js" journey-transition release proof proof started > "$JOURNEY_FILE"
"$CLI" journey set proof passed >/dev/null
assert_eq "Omitted profile preserves the active release journey" "release:ci" \
    "$(jq -r '[.profile,.current] | join(":")' "$JOURNEY_FILE")"
echo ""

echo "--- Test 2c: Journey CLI shares the active WezTerm pane state ---"
(
    unset ITERM_SESSION_ID WT_SESSION
    export WEZTERM_PANE=42 VISUALHUD_JOURNEY_PROFILE=release
    printf '%s' '{"hook_event_name":"PreToolUse","session_id":"codex-wez-session","journey_checkpoint":"proof","journey_outcome":"started"}' | bash "$ENGINE" >/dev/null
    "$CLI" journey set proof passed >/dev/null
)
assert_eq "WezTerm CLI advances the hook-owned pane journey" "ci" \
    "$(jq -r '.current' "$STATE_ROOT/visualhud-journey_42_${PROJECT_KEY}.json" 2>/dev/null || true)"
assert_eq "WezTerm CLI does not create a fallback journey" "absent" \
    "$([ -f "$STATE_ROOT/visualhud-journey_visualhud_${PROJECT_KEY}.json" ] && printf present || printf absent)"
echo ""

echo "--- Test 2d: Journey CLI keeps repository scope from nested directories ---"
node "$ROOT_DIR/scripts/visualhud-json.js" journey-transition release proof proof started > "$JOURNEY_FILE"
NESTED_PROJECT_CHECKSUM=$(printf '%s' "$ROOT_DIR/tests" | cksum)
NESTED_PROJECT_KEY=${NESTED_PROJECT_CHECKSUM%% *}
(
    unset VISUALHUD_PROJECT_ROOT
    cd "$ROOT_DIR/tests"
    "$CLI" journey set proof passed >/dev/null
)
assert_eq "Nested CLI advances the repository journey" "ci" \
    "$(jq -r '.current' "$JOURNEY_FILE" 2>/dev/null || true)"
assert_eq "Nested CLI does not create subdirectory journey state" "absent" \
    "$([ -f "$STATE_ROOT/visualhud-journey_${SESSION_KEY}_${NESTED_PROJECT_KEY}.json" ] && printf present || printf absent)"
echo ""

echo "--- Test 3: Invalid theme names are rejected without changing active theme ---"
invalid_output=$("$CLI" theme set missingno 2>&1 >/dev/null || true)
assert_contains "Invalid theme reports available-themes hint" "Unknown theme: missingno" "$invalid_output"
assert_eq "Invalid theme leaves active theme unchanged" "tmnt" "$(cat "$VISUALHUD_THEME_FILE" 2>/dev/null)"
echo ""

echo "--- Test 4: Active theme file hot-swaps on the next hook ---"
cleanup_stage() {
    rm -f "$COUNTER_FILE" "$STAGE_FILE" "$ATTENTION_FILE" "$CONTEXT_FILE" "$JOURNEY_FILE" 2>/dev/null
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
assert_eq "Active theme file overrides adapter default on next hook" "pikachu" "$(cat "$STAGE_FILE" 2>/dev/null)"

cleanup_stage
printf 'tmnt\n' > "$VISUALHUD_THEME_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Changing active theme file switches back on next hook" "tmnt-leonardo" "$(cat "$STAGE_FILE" 2>/dev/null)"

cleanup_stage
export VISUALHUD_THEME="pokemon"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Explicit VISUALHUD_THEME env still has highest priority" "pikachu" "$(cat "$STAGE_FILE" 2>/dev/null)"
echo ""

cleanup

echo "--- CLI: setup iterm2 subcommand dispatch + doctor health check ---"
SETUP_HARNESS="$TMP_ROOT/setup-harness"
mkdir -p "$SETUP_HARNESS/themes/pokemon" "$SETUP_HARNESS/themes/tmnt"
cp "$ROOT_DIR/themes/pokemon/theme.json" "$SETUP_HARNESS/themes/pokemon/theme.json"
cp "$ROOT_DIR/themes/tmnt/theme.json" "$SETUP_HARNESS/themes/tmnt/theme.json"
cp "$ROOT_DIR/engine.sh" "$SETUP_HARNESS/engine.sh"
cp "$ROOT_DIR/set_bg.py" "$SETUP_HARNESS/set_bg.py"
cp "$ROOT_DIR/visualhud" "$SETUP_HARNESS/visualhud"
mkdir -p "$SETUP_HARNESS/scripts"
cp "$ROOT_DIR/scripts/visualhud-json.js" "$SETUP_HARNESS/scripts/visualhud-json.js"
chmod +x "$SETUP_HARNESS/visualhud"

cat > "$SETUP_HARNESS/setup-iterm2.sh" <<'EOF'
#!/bin/bash
printf 'mock setup-iterm2 invoked\n'
printf 'args: %s\n' "$*"
exit 0
EOF
chmod +x "$SETUP_HARNESS/setup-iterm2.sh"

export VISUALHUD_ROOT="$SETUP_HARNESS"
set +e
setup_out="$("$SETUP_HARNESS/visualhud" setup iterm2 2>&1)"
setup_status=$?
setup_reset_out="$("$SETUP_HARNESS/visualhud" setup iterm2 --reset 2>&1)"
doctor_out="$("$SETUP_HARNESS/visualhud" doctor 2>&1)"
doctor_status=$?
set -e
assert_eq "visualhud setup iterm2 exits 0 on success" "0" "$setup_status"
assert_contains "visualhud setup iterm2 dispatches to setup-iterm2.sh" "mock setup-iterm2 invoked" "$setup_out"
assert_contains "visualhud setup iterm2 --reset forwards flags" "args: --reset" "$setup_reset_out"
assert_eq "visualhud doctor exits 0 when healthy" "0" "$doctor_status"
assert_contains "doctor reports node" "node" "$doctor_out"
assert_contains "doctor reports JSON helper" "JSON helper" "$doctor_out"
assert_contains "doctor reports python3" "python3" "$doctor_out"
assert_contains "doctor reports active theme line" "active theme" "$(printf '%s' "$doctor_out" | tr '[:upper:]' '[:lower:]')"
assert_contains "doctor reports themes directory" "themes" "$doctor_out"

unset VISUALHUD_ROOT
rm -rf "$SETUP_HARNESS"
echo ""

echo "--- setup-iterm2.sh: tab bar positioned at bottom (hero banner footer) ---"
SETUP_SCRIPT="$ROOT_DIR/setup-iterm2.sh"
TOTAL=$((TOTAL + 1))
if grep -qE 'defaults write com\.googlecode\.iterm2 TabViewType -int 1' "$SETUP_SCRIPT"; then
    PASS=$((PASS + 1))
    printf "  PASS: setup-iterm2.sh writes TabViewType=1 (bottom tab bar)\n"
else
    FAIL=$((FAIL + 1))
    printf "  FAIL: setup-iterm2.sh writes TabViewType=1 (bottom tab bar)\n"
fi
TOTAL=$((TOTAL + 1))
RESET_BLOCK=$(sed -n '/--reset/,/^fi$/p' "$SETUP_SCRIPT")
if printf '%s\n' "$RESET_BLOCK" | grep -qE 'defaults (delete|write) com\.googlecode\.iterm2 TabViewType'; then
    PASS=$((PASS + 1))
    printf "  PASS: setup-iterm2.sh --reset reverts TabViewType\n"
else
    FAIL=$((FAIL + 1))
    printf "  FAIL: setup-iterm2.sh --reset reverts TabViewType\n"
fi
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
