#!/bin/bash
# Integration tests for cooking-status.sh
# Tests the state machine: logarithmic scaling, event dispatch, attention states
#
# These tests pipe mock JSON stdin to the real script and verify:
# - State files are written correctly
# - Stage thresholds match logarithmic scaling
# - Event dispatch routes correctly
# - Attention overlays (BLOCKED/ERROR) set/clear properly

set -euo pipefail

SCRIPT_UNDER_TEST="$HOME/.claude/hooks/cooking-status.sh"
PASS=0
FAIL=0
TOTAL=0

# Use a fake session ID so we don't interfere with real sessions
TEST_SESSION="w0t0p0:TEST_SESSION_$(date +%s)"
export ITERM_SESSION_ID="$TEST_SESSION"
SESSION_KEY=$(echo "$TEST_SESSION" | tr ':/' '__')
COUNTER_FILE="/private/tmp/claude-cooking-counter_${SESSION_KEY}"
STAGE_FILE="/private/tmp/claude-cooking-stage_${SESSION_KEY}"
ATTENTION_FILE="/private/tmp/claude-cooking-attention_${SESSION_KEY}"

cleanup() {
    rm -f "$COUNTER_FILE" "$STAGE_FILE" "$ATTENTION_FILE" 2>/dev/null
}

# Run the script with mock JSON stdin, suppress TTY output
run_hook() {
    local json="$1"
    echo "$json" | bash "$SCRIPT_UNDER_TEST" 2>/dev/null || true
}

# Run with legacy argument mode (for demo.sh backward compat)
run_hook_legacy() {
    local arg="$1"
    echo "" | bash "$SCRIPT_UNDER_TEST" "$arg" 2>/dev/null || true
}

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

assert_file_not_exists() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ ! -f "$filepath" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (file should not exist: %s)\n" "$label" "$filepath"
    fi
}

# ============================================================
echo "=== Test Suite: cooking-status.sh ==="
echo ""

# --- TEST 1: Event dispatch — PreToolUse creates counter file ---
echo "--- Test 1: PreToolUse creates counter and increments ---"
cleanup
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_file_exists "Counter file created after PreToolUse" "$COUNTER_FILE"
assert_eq "Counter is 1 after first PreToolUse" "1" "$(cat "$COUNTER_FILE")"

run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Grep", "session_id": "test"}'
assert_eq "Counter is 2 after second PreToolUse" "2" "$(cat "$COUNTER_FILE")"
echo ""

# --- TEST 2: Logarithmic stage thresholds ---
echo "--- Test 2: Logarithmic stage thresholds ---"
cleanup

# Stage 1: Charmander at count 1-2
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is charmander at count 1" "charmander" "$(cat "$STAGE_FILE" 2>/dev/null)"

run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is charmander at count 2" "charmander" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Stage 2: Charmeleon at count 3-5
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is charmeleon at count 3" "charmeleon" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Fast-forward to count 6 (stage 3: Charizard, range 6-12)
printf '5' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Counter is 6" "6" "$(cat "$COUNTER_FILE")"
assert_eq "Stage file is charizard at count 6" "charizard" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Fast-forward to count 13 (stage 4: Pikachu, range 13-25)
printf '12' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is pikachu at count 13" "pikachu" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Fast-forward to count 26 (stage 5: Raichu, range 26-45)
printf '25' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is raichu at count 26" "raichu" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Fast-forward to count 46 (stage 6: Bulbasaur, range 46-75)
printf '45' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is bulbasaur at count 46" "bulbasaur" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Fast-forward to count 76 (stage 7: Ivysaur, range 76-120)
printf '75' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is ivysaur at count 76" "ivysaur" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Fast-forward to count 121 (stage 8: Venusaur, range 121-180)
printf '120' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is venusaur at count 121" "venusaur" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Fast-forward to count 181 (stage 9: Squirtle, range 181-280)
printf '180' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is squirtle at count 181" "squirtle" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Fast-forward to count 281 (stage 10: Wartortle, range 281-400)
printf '280' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is wartortle at count 281" "wartortle" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Past 400: still Wartortle (not stuck at a wrong stage)
printf '500' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is wartortle at count 501 (overflow)" "wartortle" "$(cat "$STAGE_FILE" 2>/dev/null)"
echo ""

# --- TEST 3: Stop event sets done state and clears counter ---
echo "--- Test 3: Stop event sets Blastoise and clears counter ---"
cleanup
# First create some state
printf '50' > "$COUNTER_FILE"
printf 'bulbasaur' > "$STAGE_FILE"

run_hook '{"hook_event_name": "Stop", "session_id": "test"}'
assert_file_not_exists "Counter file deleted after Stop" "$COUNTER_FILE"
assert_file_not_exists "Attention file deleted after Stop" "$ATTENTION_FILE"
assert_eq "Stage file is blastoise after Stop" "blastoise" "$(cat "$STAGE_FILE" 2>/dev/null)"
echo ""

# --- TEST 4: UserPromptSubmit resets counter ---
echo "--- Test 4: UserPromptSubmit resets counter ---"
cleanup
printf '100' > "$COUNTER_FILE"
printf 'ivysaur' > "$STAGE_FILE"
printf 'blocked' > "$ATTENTION_FILE"

run_hook '{"hook_event_name": "UserPromptSubmit", "prompt": "do something", "session_id": "test"}'
assert_file_not_exists "Counter file deleted after UserPromptSubmit" "$COUNTER_FILE"
assert_file_not_exists "Attention file deleted after UserPromptSubmit" "$ATTENTION_FILE"
echo ""

# --- TEST 5: Notification(permission_prompt) sets BLOCKED ---
echo "--- Test 5: Notification(permission_prompt) sets BLOCKED attention ---"
cleanup
printf '50' > "$COUNTER_FILE"

run_hook '{"hook_event_name": "Notification", "notification_type": "permission_prompt", "message": "Claude needs permission", "session_id": "test"}'
assert_file_exists "Attention file created for BLOCKED" "$ATTENTION_FILE"
assert_eq "Attention file contains 'blocked'" "blocked" "$(cat "$ATTENTION_FILE" 2>/dev/null)"
assert_eq "Stage file is snorlax when BLOCKED" "snorlax" "$(cat "$STAGE_FILE" 2>/dev/null)"
# Counter should NOT be affected
assert_eq "Counter unchanged during BLOCKED" "50" "$(cat "$COUNTER_FILE" 2>/dev/null)"
echo ""

# --- TEST 6: Non-permission notifications are ignored ---
echo "--- Test 6: Non-permission notifications are ignored ---"
cleanup

run_hook '{"hook_event_name": "Notification", "notification_type": "auth_success", "session_id": "test"}'
assert_file_not_exists "No attention file for auth_success" "$ATTENTION_FILE"
echo ""

# --- TEST 7: StopFailure sets ERROR ---
echo "--- Test 7: StopFailure sets ERROR attention ---"
cleanup
printf '30' > "$COUNTER_FILE"

run_hook '{"hook_event_name": "StopFailure", "error": "rate_limit", "session_id": "test"}'
assert_file_exists "Attention file created for ERROR" "$ATTENTION_FILE"
assert_eq "Attention file contains 'error'" "error" "$(cat "$ATTENTION_FILE" 2>/dev/null)"
echo ""

# --- TEST 8: PreToolUse clears attention state ---
echo "--- Test 8: PreToolUse clears attention state (user granted permission) ---"
cleanup
printf '50' > "$COUNTER_FILE"
printf 'blocked' > "$ATTENTION_FILE"

run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "test"}'
assert_file_not_exists "Attention file cleared after PreToolUse" "$ATTENTION_FILE"
assert_eq "Counter incremented despite clearing attention" "51" "$(cat "$COUNTER_FILE")"
echo ""

# --- TEST 9: Legacy argument mode still works (for demo.sh) ---
echo "--- Test 9: Legacy argument mode backward compat ---"
cleanup

run_hook_legacy "cooking"
assert_file_exists "Counter file created in legacy mode" "$COUNTER_FILE"
assert_eq "Counter is 1 in legacy cooking mode" "1" "$(cat "$COUNTER_FILE")"

run_hook_legacy "cooked"
assert_file_not_exists "Counter deleted in legacy cooked mode" "$COUNTER_FILE"
echo ""

# --- TEST 10: Full lifecycle ---
echo "--- Test 10: Full lifecycle (prompt → work → blocked → unblock → done) ---"
cleanup

# User submits prompt
run_hook '{"hook_event_name": "UserPromptSubmit", "prompt": "fix the bug", "session_id": "test"}'
assert_file_not_exists "No counter after prompt (waiting for first tool call)" "$COUNTER_FILE"

# Claude starts working (5 tool calls)
for i in 1 2 3 4 5; do
    run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
done
assert_eq "Counter is 5 after 5 PreToolUse calls" "5" "$(cat "$COUNTER_FILE")"
assert_eq "Stage is charmeleon at count 5" "charmeleon" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Claude gets blocked on permission
run_hook '{"hook_event_name": "Notification", "notification_type": "permission_prompt", "message": "need bash", "session_id": "test"}'
assert_eq "Attention is blocked" "blocked" "$(cat "$ATTENTION_FILE" 2>/dev/null)"
assert_eq "Counter unchanged during block" "5" "$(cat "$COUNTER_FILE")"

# User grants permission, Claude continues
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "test"}'
assert_file_not_exists "Attention cleared after unblock" "$ATTENTION_FILE"
assert_eq "Counter is 6 after unblock" "6" "$(cat "$COUNTER_FILE")"
assert_eq "Stage is charizard at count 6" "charizard" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Claude finishes
run_hook '{"hook_event_name": "Stop", "session_id": "test"}'
assert_file_not_exists "Counter cleared after Stop" "$COUNTER_FILE"
assert_eq "Stage is blastoise (done)" "blastoise" "$(cat "$STAGE_FILE" 2>/dev/null)"
echo ""

# --- TEST 11: Notification(idle_prompt) triggers done state (Stop backup) ---
echo "--- Test 11: idle_prompt notification triggers done state ---"
cleanup
printf '50' > "$COUNTER_FILE"
printf 'bulbasaur' > "$STAGE_FILE"
printf 'blocked' > "$ATTENTION_FILE"

run_hook '{"hook_event_name": "Notification", "notification_type": "idle_prompt", "session_id": "test"}'
assert_file_not_exists "Counter cleared after idle_prompt" "$COUNTER_FILE"
assert_file_not_exists "Attention cleared after idle_prompt" "$ATTENTION_FILE"
assert_eq "Stage is blastoise after idle_prompt" "blastoise" "$(cat "$STAGE_FILE" 2>/dev/null)"
echo ""

# --- TEST 12: idle_prompt with no prior state still sets done ---
echo "--- Test 12: idle_prompt with clean state still sets done ---"
cleanup

run_hook '{"hook_event_name": "Notification", "notification_type": "idle_prompt", "session_id": "test"}'
assert_eq "Stage is blastoise after idle_prompt (clean state)" "blastoise" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_file_not_exists "No counter file after idle_prompt" "$COUNTER_FILE"
echo ""

# --- TEST 13: Full lifecycle with idle_prompt instead of Stop ---
echo "--- Test 13: Lifecycle with idle_prompt as Stop backup ---"
cleanup

# Work happens
for i in 1 2 3 4 5 6; do
    run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
done
assert_eq "Counter is 6 after work" "6" "$(cat "$COUNTER_FILE")"
assert_eq "Stage is charizard during work" "charizard" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Claude goes idle (Stop hook didn't fire — known bug)
run_hook '{"hook_event_name": "Notification", "notification_type": "idle_prompt", "session_id": "test"}'
assert_file_not_exists "Counter cleared by idle_prompt" "$COUNTER_FILE"
assert_eq "Stage is blastoise via idle_prompt backup" "blastoise" "$(cat "$STAGE_FILE" 2>/dev/null)"
echo ""

# --- TEST 14: progress_bar function outputs correct format ---
echo "--- Test 14: progress_bar function output ---"

# Extract and test the progress_bar function from the real script
eval "$(sed -n '/^progress_bar()/,/^}/p' "$SCRIPT_UNDER_TEST")"

assert_eq "Progress bar stage 1" "🟥" "$(progress_bar 1)"
assert_eq "Progress bar stage 6" "🟥🟥🟧🟨🟨🟩" "$(progress_bar 6)"
assert_eq "Progress bar stage 11 (full)" "🟥🟥🟧🟨🟨🟩🟩🟩🟦🟦🟦" "$(progress_bar 11)"
assert_eq "Progress bar stage 0 (empty)" "" "$(progress_bar 0)"
echo ""

# --- TEST 15: Title includes project name (not "Claude Code") ---
echo "--- Test 15: Title uses project name from PWD ---"
cleanup

# Set PWD to a known project dir and verify PROJECT_NAME would be derived
SAVED_PWD="$PWD"
cd /tmp
export PWD="/tmp"

# Run a hook — the script should use basename of PWD for title
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage is charmander at count 1" "charmander" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Verify the script contains PROJECT_NAME (proves the refactor happened)
if grep -q 'PROJECT_NAME' "$SCRIPT_UNDER_TEST"; then
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    printf "  PASS: Script contains PROJECT_NAME variable\n"
else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    printf "  FAIL: Script should contain PROJECT_NAME variable\n"
fi

cd "$SAVED_PWD"
echo ""

# --- TEST 16: setup-iterm2.sh enables per-pane title bars ---
echo "--- Test 16: setup-iterm2.sh includes ShowPaneTitles ---"
SETUP_SCRIPT="$HOME/visualhud/setup-iterm2.sh"
if grep -q 'ShowPaneTitles' "$SETUP_SCRIPT"; then
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    printf "  PASS: setup-iterm2.sh contains ShowPaneTitles\n"
else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    printf "  FAIL: setup-iterm2.sh should contain ShowPaneTitles\n"
fi
echo ""

# --- TEST 17: Script uses SetUserVar for Claude-proof title ---
echo "--- Test 17: Script uses SetUserVar for Claude-proof title ---"
if grep -q 'SetUserVar' "$SCRIPT_UNDER_TEST"; then
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    printf "  PASS: Script uses SetUserVar escape sequence\n"
else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    printf "  FAIL: Script should use SetUserVar for hudProgress\n"
fi
if grep -q 'hudProgress' "$SCRIPT_UNDER_TEST"; then
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    printf "  PASS: Script references hudProgress variable\n"
else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    printf "  FAIL: Script should reference hudProgress variable\n"
fi
echo ""

# ============================================================
# Cleanup
cleanup

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
