#!/bin/bash
# Integration tests for Claude Code VisualHUD: escape-sequence verification.
#
# Fires real hook events through the Claude adapter + engine and captures
# the terminal escape sequences via VISUALHUD_TTY. Verifies that correct
# colors, badges, and titles are emitted for each lifecycle state.
#
# Unlike test-claude-visualhud.sh (which mocks the engine), these tests
# run the real engine. Coverage is escape-sequence level, not live terminal.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="$ROOT_DIR/.claude/hooks/visualhud-claude.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-claude-integration.XXXXXX")"
CAPTURE="$TMP_ROOT/capture.out"
STATE_DIR="$TMP_ROOT/state"

cleanup() {
    rm -rf "$TMP_ROOT"
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
        printf "  FAIL: %s (expected to contain '%s')\n" "$label" "$needle"
    fi
}

assert_not_empty() {
    local label="$1" value="$2"
    TOTAL=$((TOTAL + 1))
    if [ -n "$value" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (value was empty)\n" "$label"
    fi
}

assert_file_nonempty() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ -s "$filepath" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (file empty or missing: %s)\n" "$label" "$filepath"
    fi
}

assert_match() {
    local label="$1" pattern="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if printf '%s' "$haystack" | grep -qE "$pattern"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (no match for pattern '%s')\n" "$label" "$pattern"
    fi
}

# Extract base64-decoded value of a SetUserVar from capture
extract_uservar() {
    local capture="$1" varname="$2"
    grep -o "SetUserVar=${varname}=[A-Za-z0-9+/=]*" "$capture" | tail -1 | \
        sed "s/SetUserVar=${varname}=//" | base64 -d 2>/dev/null || true
}

# Extract tab color from capture (SetColors=tab=RRGGBB)
extract_tab_color() {
    local capture="$1"
    grep -o 'SetColors=tab=[0-9a-f]*' "$capture" | tail -1 | sed 's/SetColors=tab=//' || true
}

# Extract badge from capture (SetBadgeFormat=base64)
extract_badge() {
    local capture="$1"
    grep -o 'SetBadgeFormat=[A-Za-z0-9+/=]*' "$capture" | tail -1 | \
        sed 's/SetBadgeFormat=//' | base64 -d 2>/dev/null || true
}

# Fire a Claude hook event and capture output
fire_event() {
    local payload="$1"
    : > "$CAPTURE"
    printf '%s' "$payload" | \
        VISUALHUD_TTY="$CAPTURE" \
        VISUALHUD_STATE_DIR="$STATE_DIR" \
        VISUALHUD_REAPPLY_DELAY=0 \
        VISUALHUD_BG=off \
        VISUALHUD_JOURNEY_PROFILE=off \
        ITERM_SESSION_ID="w0t0p0:CLAUDE_INTEGRATION_TEST" \
        bash "$ADAPTER" >/dev/null 2>/dev/null || true
}

mkdir -p "$STATE_DIR"

echo "=== Test Suite: Claude Code VisualHUD Integration ==="
echo ""

# ============================================================
# TEST 1: PreToolUse fires and produces escape sequences
# ============================================================
echo "--- Test 1: PreToolUse produces terminal escape sequences ---"
fire_event '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"test-session"}'
assert_file_nonempty "PreToolUse capture file has content" "$CAPTURE"
assert_contains "PreToolUse emits SetBadgeFormat" "SetBadgeFormat=" "$(cat "$CAPTURE")"
assert_contains "PreToolUse emits tab color" "SetColors=tab=" "$(cat "$CAPTURE")"
assert_contains "PreToolUse emits hudProgress user var" "SetUserVar=hudProgress=" "$(cat "$CAPTURE")"

badge=$(extract_badge "$CAPTURE")
assert_not_empty "PreToolUse badge is non-empty" "$badge"

tab_color=$(extract_tab_color "$CAPTURE")
assert_not_empty "PreToolUse tab color is non-empty" "$tab_color"

title=$(extract_uservar "$CAPTURE" "hudProgress")
assert_not_empty "PreToolUse title is non-empty" "$title"
echo ""

# ============================================================
# TEST 2: Stop event produces done state
# ============================================================
echo "--- Test 2: Stop event produces done state ---"
fire_event '{"hook_event_name":"Stop","session_id":"test-session"}'
assert_file_nonempty "Stop capture file has content" "$CAPTURE"

badge=$(extract_badge "$CAPTURE")
assert_not_empty "Stop badge is non-empty" "$badge"
echo ""

# ============================================================
# TEST 3: Pokemon theme renders correct working state with valid colors
# ============================================================
echo "--- Test 3: Pokemon theme renders correct working state ---"
SESSION_KEY="w0t0p0_CLAUDE_INTEGRATION_TEST"
COUNTER_FILE="$STATE_DIR/claude-cooking-counter_${SESSION_KEY}"

fire_event '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"test-session"}'

if [ -f "$COUNTER_FILE" ]; then
    counter_val=$(cat "$COUNTER_FILE")
    assert_not_empty "Counter file tracks tool calls" "$counter_val"
else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    printf "  FAIL: No counter file written at %s\n" "$COUNTER_FILE"
fi

badge=$(extract_badge "$CAPTURE")
tab_color=$(extract_tab_color "$CAPTURE")
assert_not_empty "Working state has badge" "$badge"
assert_match "Tab color is valid hex" '^[0-9a-f]{6}$' "$tab_color"
echo ""

# ============================================================
# TEST 4: Theme switch changes tab color
# ============================================================
echo "--- Test 4: Theme switch changes tab color ---"
fire_event '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"test-session"}'
color_pokemon=$(extract_tab_color "$CAPTURE")

VISUALHUD_THEME=tmnt fire_event '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"test-session"}'
color_tmnt=$(extract_tab_color "$CAPTURE")

assert_not_empty "Pokemon tab color captured" "$color_pokemon"
assert_not_empty "TMNT tab color captured" "$color_tmnt"
TOTAL=$((TOTAL + 1))
if [ "$color_pokemon" != "$color_tmnt" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: Pokemon (%s) and TMNT (%s) have different tab colors\n" "$color_pokemon" "$color_tmnt"
else
    FAIL=$((FAIL + 1))
    printf "  FAIL: Pokemon and TMNT tab colors are identical (%s)\n" "$color_pokemon"
fi
echo ""

# ============================================================
# TEST 5: Multiple PreToolUse events don't corrupt state
# ============================================================
echo "--- Test 5: Rapid sequential events maintain consistent state ---"
for _ in 1 2 3 4 5; do
    fire_event '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"test-session"}'
done
assert_file_nonempty "5th PreToolUse still produces output" "$CAPTURE"

badge=$(extract_badge "$CAPTURE")
assert_not_empty "Badge still renders after 5 events" "$badge"

tab_color=$(extract_tab_color "$CAPTURE")
assert_not_empty "Tab color still renders after 5 events" "$tab_color"
echo ""

# ============================================================
# TEST 6: Notification event renders
# ============================================================
echo "--- Test 6: Notification event renders ---"
fire_event '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs permission","session_id":"test-session"}'
assert_file_nonempty "Notification capture has content" "$CAPTURE"
assert_contains "Notification emits badge" "SetBadgeFormat=" "$(cat "$CAPTURE")"
echo ""

# ============================================================
# TEST 7: UserPromptSubmit is accepted without error (silent event)
# ============================================================
echo "--- Test 7: UserPromptSubmit is accepted without error ---"
: > "$CAPTURE"
printf '{"hook_event_name":"UserPromptSubmit","session_id":"test-session","prompt":"hello"}' | \
    VISUALHUD_TTY="$CAPTURE" VISUALHUD_STATE_DIR="$STATE_DIR" VISUALHUD_REAPPLY_DELAY=0 \
    VISUALHUD_BG=off VISUALHUD_JOURNEY_PROFILE=off \
    ITERM_SESSION_ID="w0t0p0:CLAUDE_INTEGRATION_TEST" \
    bash "$ADAPTER" >/dev/null 2>/dev/null
assert_eq "UserPromptSubmit exits cleanly" "0" "$?"
echo ""

# ============================================================
# TEST 8: StopFailure event renders (error state)
# ============================================================
echo "--- Test 8: StopFailure event renders error state ---"
fire_event '{"hook_event_name":"StopFailure","session_id":"test-session"}'
assert_file_nonempty "StopFailure capture has content" "$CAPTURE"
assert_contains "StopFailure emits badge" "SetBadgeFormat=" "$(cat "$CAPTURE")"
echo ""

# ============================================================
# TEST 9: SessionStart is accepted without error (silent event)
# ============================================================
echo "--- Test 9: SessionStart is accepted without error ---"
: > "$CAPTURE"
printf '{"hook_event_name":"SessionStart","session_id":"test-session","source":"startup"}' | \
    VISUALHUD_TTY="$CAPTURE" VISUALHUD_STATE_DIR="$STATE_DIR" VISUALHUD_REAPPLY_DELAY=0 \
    VISUALHUD_BG=off VISUALHUD_JOURNEY_PROFILE=off \
    ITERM_SESSION_ID="w0t0p0:CLAUDE_INTEGRATION_TEST" \
    bash "$ADAPTER" >/dev/null 2>/dev/null
assert_eq "SessionStart exits cleanly" "0" "$?"
echo ""

# ============================================================
# TEST 10: All installed themes produce valid output
# ============================================================
echo "--- Test 10: All themes produce valid output ---"
THEME_COUNT=0
for theme_dir in "$ROOT_DIR/themes"/*/; do
    theme=$(basename "$theme_dir")
    [ -f "$ROOT_DIR/themes/$theme/theme.json" ] || continue
    THEME_COUNT=$((THEME_COUNT + 1))
    VISUALHUD_THEME="$theme" fire_event '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"test-session"}'
    assert_file_nonempty "$theme theme produces output" "$CAPTURE"

    badge=$(extract_badge "$CAPTURE")
    assert_not_empty "$theme badge is non-empty" "$badge"

    tab_color=$(extract_tab_color "$CAPTURE")
    assert_not_empty "$theme tab color is non-empty" "$tab_color"
done
TOTAL=$((TOTAL + 1))
if [ "$THEME_COUNT" -ge 1 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: Tested %d themes (discovered from themes/ dir)\n" "$THEME_COUNT"
else
    FAIL=$((FAIL + 1))
    printf "  FAIL: No themes found in themes/ dir\n"
fi
echo ""

# ============================================================
# TEST 11: Background color sequences are valid hex
# ============================================================
echo "--- Test 11: Color sequences are valid hex ---"
fire_event '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"test-session"}'
capture_content=$(cat "$CAPTURE")

bg_color=$(printf '%s' "$capture_content" | grep -o 'SetColors=bg=[0-9a-f]*' | tail -1 | sed 's/SetColors=bg=//' || true)
assert_not_empty "Background color is present" "$bg_color"
assert_match "Background color is valid hex" '^[0-9a-f]{6}$' "$bg_color"

sel_color=$(printf '%s' "$capture_content" | grep -o 'SetColors=selbg=[0-9a-f]*' | tail -1 | sed 's/SetColors=selbg=//' || true)
assert_not_empty "Selection color is present" "$sel_color"
assert_match "Selection color is valid hex" '^[0-9a-f]{6}$' "$sel_color"

cur_color=$(printf '%s' "$capture_content" | grep -o 'SetColors=curbg=[0-9a-f]*' | tail -1 | sed 's/SetColors=curbg=//' || true)
assert_not_empty "Cursor color is present" "$cur_color"
assert_match "Cursor color is valid hex" '^[0-9a-f]{6}$' "$cur_color"
echo ""

# ============================================================
# TEST 12: Unsupported events are silently ignored
# ============================================================
echo "--- Test 12: Unsupported events are silently ignored ---"
: > "$CAPTURE"
fire_event '{"hook_event_name":"FakeEvent","session_id":"test-session"}'
TOTAL=$((TOTAL + 1))
if [ ! -s "$CAPTURE" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: Unsupported event produces no output\n"
else
    FAIL=$((FAIL + 1))
    printf "  FAIL: Unsupported event should produce no output (%s bytes)\n" "$(wc -c < "$CAPTURE" | tr -d ' ')"
fi
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
