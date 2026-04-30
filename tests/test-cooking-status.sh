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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_UNDER_TEST="${VISUALHUD_ENGINE_UNDER_TEST:-$ROOT_DIR/engine.sh}"
PASS=0
FAIL=0
TOTAL=0
export VISUALHUD_THEMES_DIR="$ROOT_DIR/themes"

# Use a fake session ID so we don't interfere with real sessions
TEST_SESSION="w0t0p0:TEST_SESSION_$(date +%s)"
export ITERM_SESSION_ID="$TEST_SESSION"
SESSION_KEY=$(echo "$TEST_SESSION" | tr ':/' '__')
COUNTER_FILE="/private/tmp/claude-cooking-counter_${SESSION_KEY}"
STAGE_FILE="/private/tmp/claude-cooking-stage_${SESSION_KEY}"
ATTENTION_FILE="/private/tmp/claude-cooking-attention_${SESSION_KEY}"
CONTEXT_FILE="/private/tmp/claude-cooking-context_${SESSION_KEY}"
REVIEW_FILE="/private/tmp/claude-cooking-review_${SESSION_KEY}"

cleanup() {
    rm -f "$COUNTER_FILE" "$STAGE_FILE" "$ATTENTION_FILE" "$CONTEXT_FILE" "$REVIEW_FILE" 2>/dev/null
    unset VISUALHUD_THEME VISUALHUD_SET_BG VISUALHUD_SET_BG_LOG VISUALHUD_SPRITES_DIR
    unset VISUALHUD_TTY VISUALHUD_CONTEXT_USED_PERCENT VISUALHUD_CODEX_SESSION_FILE CODEX_HOME
    unset VISUALHUD_REAPPLY_DELAY
    export VISUALHUD_THEMES_DIR="$ROOT_DIR/themes"
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

# Fast-forward to count 401 (stage 11: Blastoise, overflow)
printf '400' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is blastoise at count 401" "blastoise" "$(cat "$STAGE_FILE" 2>/dev/null)"

# Past 520: Blastoise remains the shipped Pokemon overflow until ghost art exists.
printf '520' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is blastoise at count 521" "blastoise" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '900' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Stage file is blastoise at count 901 (overflow)" "blastoise" "$(cat "$STAGE_FILE" 2>/dev/null)"
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

# --- TEST 3b: Review work does not false-advertise done ---
echo "--- Test 3b: Code review stays in review state until TaskCompleted ---"
cleanup
REVIEW_TTY="${TMPDIR:-/tmp}/visualhud-review-state-$$.log"
export VISUALHUD_TTY="$REVIEW_TTY"
export VISUALHUD_THEME="pokemon"
: > "$REVIEW_TTY"

run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "codex exec -o .reviews/latest-review.md \"Review v1.42.0 before ship\""}, "session_id": "test"}'
assert_file_exists "Review marker is created for code review work" "$REVIEW_FILE"
assert_eq "Pokemon review uses Wartortle instead of Blastoise" "wartortle" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Review title is explicit" "Reviewing" "$(cat "$REVIEW_TTY" 2>/dev/null)"

: > "$REVIEW_TTY"
run_hook '{"hook_event_name": "Stop", "session_id": "test", "last_assistant_message": "Waiting for code review to finish."}'
assert_file_exists "Review marker remains after Stop while review is active" "$REVIEW_FILE"
assert_eq "Stop while reviewing preserves Wartortle" "wartortle" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Stop while reviewing does not show Your turn" "Reviewing" "$(cat "$REVIEW_TTY" 2>/dev/null)"

: > "$REVIEW_TTY"
run_hook '{"hook_event_name": "TaskCompleted", "session_id": "test", "task": "code review completed"}'
assert_file_not_exists "Review marker clears after TaskCompleted" "$REVIEW_FILE"
assert_eq "TaskCompleted after review can finally show Blastoise" "blastoise" "$(cat "$STAGE_FILE" 2>/dev/null)"
rm -f "$REVIEW_TTY"
echo ""

# --- TEST 4: UserPromptSubmit resets counter ---
echo "--- Test 4: UserPromptSubmit resets counter ---"
cleanup
printf '100' > "$COUNTER_FILE"
printf 'ivysaur' > "$STAGE_FILE"
printf 'blocked' > "$ATTENTION_FILE"
printf 'review' > "$REVIEW_FILE"

run_hook '{"hook_event_name": "UserPromptSubmit", "prompt": "do something", "session_id": "test"}'
assert_file_not_exists "Counter file deleted after UserPromptSubmit" "$COUNTER_FILE"
assert_file_not_exists "Attention file deleted after UserPromptSubmit" "$ATTENTION_FILE"
assert_file_not_exists "Review marker deleted after UserPromptSubmit" "$REVIEW_FILE"
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
for _ in 1 2 3 4 5; do
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
for _ in 1 2 3 4 5 6; do
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
export THEME_FILE="$ROOT_DIR/themes/pokemon/theme.json"
eval "$(sed -n '/^progress_bar()/,/^}/p' "$SCRIPT_UNDER_TEST")"

assert_eq "Progress bar stage 1" "🟥" "$(progress_bar 1)"
assert_eq "Progress bar stage 6" "🟥🟥🟧🟨🟨🟩" "$(progress_bar 6)"
assert_eq "Progress bar stage 11 (full)" "🟥🟥🟧🟨🟨🟩🟩🟩🟦🟦🟦" "$(progress_bar 11)"
assert_eq "Progress bar stage beyond Pokemon sprite pack stays capped" "🟥🟥🟧🟨🟨🟩🟩🟩🟦🟦🟦" "$(progress_bar 14)"
assert_eq "Progress bar stage 0 (empty)" "" "$(progress_bar 0)"

export THEME_FILE="$ROOT_DIR/themes/tmnt/theme.json"
assert_eq "TMNT progress bar uses visual color blocks, not character initials" \
    "🟥🟥🟧🟨🟨🟩🟩🟩🟦🟦🟦" \
    "$(progress_bar 11)"
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

# --- TEST 18: TMNT theme swaps actual stage sprites ---
echo "--- Test 18: TMNT theme swaps actual stage sprites ---"
cleanup
export VISUALHUD_THEME="tmnt"

run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT count 1 uses Leonardo sprite" "tmnt-leonardo" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '2' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT count 3 uses Michelangelo sprite" "tmnt-michelangelo" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '5' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT count 6 uses Donatello sprite" "tmnt-donatello" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '12' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT count 13 uses Raphael sprite" "tmnt-raphael" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '25' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT count 26 uses April sprite" "tmnt-april" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '45' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT count 46 uses Metalhead sprite" "tmnt-metalhead" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '75' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT count 76 uses Mutagen sprite" "tmnt-mutagen" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '120' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT count 121 uses Splinter sprite" "tmnt-splinter" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '180' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT count 181 uses Krang sprite" "tmnt-krang" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '280' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT count 281 uses Foot Clan sprite" "tmnt-foot-clan" "$(cat "$STAGE_FILE" 2>/dev/null)"

printf '500' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "TMNT overflow uses Turtle Power sprite" "tmnt-turtle-power" "$(cat "$STAGE_FILE" 2>/dev/null)"
echo ""

# --- TEST 19: TMNT theme maps lifecycle states to themed sprites ---
echo "--- Test 19: TMNT theme maps lifecycle states to themed sprites ---"
cleanup
export VISUALHUD_THEME="tmnt"
TMNT_LIFECYCLE_TTY="${TMPDIR:-/tmp}/visualhud-tmnt-lifecycle-$$.log"
export VISUALHUD_TTY="$TMNT_LIFECYCLE_TTY"
: > "$TMNT_LIFECYCLE_TTY"

run_hook '{"hook_event_name": "Notification", "notification_type": "permission_prompt", "message": "needs approval", "session_id": "test"}'
assert_eq "TMNT blocked uses Shredder sprite" "tmnt-shredder" "$(cat "$STAGE_FILE" 2>/dev/null)"

: > "$TMNT_LIFECYCLE_TTY"
run_hook '{"hook_event_name": "Stop", "session_id": "test"}'
assert_eq "TMNT Stop uses pizza sprite" "tmnt-pizza" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "TMNT Stop emits Turtle Power success tab color, not April yellow" \
    "SetColors=tab=14b955" \
    "$(cat "$TMNT_LIFECYCLE_TTY" 2>/dev/null)"
assert_contains "TMNT Stop title uses visual progress blocks instead of initials" \
    "🟥🟥🟧🟨🟨🟩🟩🟩🟦🟦🟦 PIZZA Pizza Party" \
    "$(cat "$TMNT_LIFECYCLE_TTY" 2>/dev/null)"

run_hook '{"hook_event_name": "Notification", "notification_type": "idle_prompt", "session_id": "test"}'
assert_eq "TMNT idle uses Splinter sprite" "tmnt-splinter" "$(cat "$STAGE_FILE" 2>/dev/null)"

: > "$TMNT_LIFECYCLE_TTY"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Task", "tool_input": {"description": "Run code review before shipping"}, "session_id": "test"}'
assert_file_exists "TMNT review marker is created" "$REVIEW_FILE"
assert_eq "TMNT review uses Splinter review sprite" "tmnt-splinter" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "TMNT review title is explicit" "Splinter Review" "$(cat "$TMNT_LIFECYCLE_TTY" 2>/dev/null)"

: > "$TMNT_LIFECYCLE_TTY"
run_hook '{"hook_event_name": "Stop", "session_id": "test"}'
assert_eq "TMNT Stop while reviewing does not use pizza sprite" "tmnt-splinter" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "TMNT Stop while reviewing keeps review title" "Splinter Review" "$(cat "$TMNT_LIFECYCLE_TTY" 2>/dev/null)"
rm -f "$TMNT_LIFECYCLE_TTY"
echo ""

# --- TEST 20: TMNT theme covers an expanded color spectrum ---
echo "--- Test 20: TMNT theme covers expanded color spectrum ---"
TMNT_THEME_FILE="$ROOT_DIR/themes/tmnt/theme.json"
assert_eq "TMNT stages use full character/item roster" \
    "Leonardo,Michelangelo,Donatello,Raphael,April,Metalhead,Mutagen,Splinter,Krang,Foot Clan,Turtle Power" \
    "$(jq -r '[.stages[].name] | join(",")' "$TMNT_THEME_FILE")"
assert_eq "TMNT stage badges cover full spectrum" \
    "L,M,D,R,A,MH,MU,S,K,F,T" \
    "$(jq -r '[.stages[].badge] | join(",")' "$TMNT_THEME_FILE")"
assert_eq "TMNT stage colors cover blue/orange/purple/red/yellow/gray/green/brown/pink/steel/green" \
    "25-105-255,255-125-25,150-80-255,255-55-55,255-220-45,185-185-185,40-220-90,130-95-65,255-95-190,95-85-120,20-185-85" \
    "$(jq -r '[.stages[].color | join("-")] | join(",")' "$TMNT_THEME_FILE")"
assert_eq "TMNT stages declare color families" \
    "blue,orange,purple,red,yellow,metal,green,brown,pink,steel,green" \
    "$(jq -r '[.stages[].color_family] | join(",")' "$TMNT_THEME_FILE")"
echo ""

# --- TEST 21: Theme-local sprite assets drive background swaps ---
echo "--- Test 21: Theme-local sprite assets drive background swaps ---"
cleanup
TMP_THEME_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-theme-test.XXXXXX")
mkdir -p "$TMP_THEME_ROOT/tmnt/sprites"
cp "$ROOT_DIR/themes/tmnt/theme.json" "$TMP_THEME_ROOT/tmnt/theme.json"
: > "$TMP_THEME_ROOT/tmnt/sprites/tmnt-leonardo.png"
MOCK_SET_BG="$TMP_THEME_ROOT/set_bg.py"
SET_BG_LOG="$TMP_THEME_ROOT/set-bg.log"
cat > "$MOCK_SET_BG" <<'PY'
import os
import sys

with open(os.environ["VISUALHUD_SET_BG_LOG"], "a", encoding="utf-8") as handle:
    handle.write(sys.argv[1] + "\n")
PY

export VISUALHUD_THEME="tmnt"
export VISUALHUD_THEMES_DIR="$TMP_THEME_ROOT"
export VISUALHUD_SET_BG="$MOCK_SET_BG"
export VISUALHUD_SET_BG_LOG="$SET_BG_LOG"
export VISUALHUD_SPRITES_DIR="$TMP_THEME_ROOT/global-sprites"

run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
for _ in 1 2 3 4 5; do
    [ -f "$SET_BG_LOG" ] && break
    sleep 0.1
done
assert_eq "Theme-local TMNT sprite passed to set_bg" \
    "$TMP_THEME_ROOT/tmnt/sprites/tmnt-leonardo.png" \
    "$(head -n 1 "$SET_BG_LOG" 2>/dev/null)"
rm -rf "$TMP_THEME_ROOT"
cleanup
echo ""

# --- TEST 22: Missing theme sprites clear stale background art ---
echo "--- Test 22: Missing theme sprites clear stale background art ---"
cleanup
TMP_THEME_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-theme-test.XXXXXX")
mkdir -p "$TMP_THEME_ROOT/tmnt"
cp "$ROOT_DIR/themes/tmnt/theme.json" "$TMP_THEME_ROOT/tmnt/theme.json"
MOCK_SET_BG="$TMP_THEME_ROOT/set_bg.py"
SET_BG_LOG="$TMP_THEME_ROOT/set-bg.log"
cat > "$MOCK_SET_BG" <<'PY'
import os
import sys

with open(os.environ["VISUALHUD_SET_BG_LOG"], "a", encoding="utf-8") as handle:
    handle.write((sys.argv[1] if len(sys.argv) > 1 else "") + "\n")
PY

export VISUALHUD_THEME="tmnt"
export VISUALHUD_THEMES_DIR="$TMP_THEME_ROOT"
export VISUALHUD_SET_BG="$MOCK_SET_BG"
export VISUALHUD_SET_BG_LOG="$SET_BG_LOG"
export VISUALHUD_SPRITES_DIR="$TMP_THEME_ROOT/global-sprites"

printf 'snorlax' > "$STAGE_FILE"
run_hook '{"hook_event_name": "Notification", "notification_type": "permission_prompt", "message": "needs approval", "session_id": "test"}'
for _ in 1 2 3 4 5; do
    [ -f "$SET_BG_LOG" ] && break
    sleep 0.1
done
assert_file_exists "Missing TMNT sprite still invokes set_bg" "$SET_BG_LOG"
assert_eq "Missing TMNT sprite clears stale background" "" "$(head -n 1 "$SET_BG_LOG" 2>/dev/null)"
rm -rf "$TMP_THEME_ROOT"
cleanup
echo ""

# --- TEST 23: Repo-local background helper exists for Codex runtime ---
echo "--- Test 23: Repo-local background helper exists for Codex runtime ---"
assert_file_exists "Repo-local set_bg.py exists" "$ROOT_DIR/set_bg.py"
echo ""

# --- TEST 24: iTerm badge text stays compact ---
echo "--- Test 24: iTerm badge text stays compact ---"
BADGE_FN=$(sed -n '/^badge_text_for()/,/^}/p' "$SCRIPT_UNDER_TEST")
if [ -n "$BADGE_FN" ]; then
    eval "$BADGE_FN"
fi
if type badge_text_for >/dev/null 2>&1; then
    actual_done_badge="$(badge_text_for "PIZZA" "Pizza Party" 11)"
    actual_progress_badge="$(badge_text_for "MH" "Metalhead" 6)"
else
    actual_done_badge="__missing__"
    actual_progress_badge="__missing__"
fi
assert_eq "Done badge omits progress bar and stage name" "PIZZA" "$actual_done_badge"
assert_eq "Progress badge omits progress bar and stage name" "MH" "$actual_progress_badge"
echo ""

# --- TEST 25: TMNT sprite assets must be source-backed, not placeholders ---
echo "--- Test 25: TMNT sprite assets must be source-backed, not placeholders ---"
TMNT_SPRITES_DIR="$ROOT_DIR/themes/tmnt/sprites"
TMNT_SPRITE_COUNT=0
if [ -d "$TMNT_SPRITES_DIR" ]; then
    TMNT_SPRITE_COUNT=$(find "$TMNT_SPRITES_DIR" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')
fi
if [ "$TMNT_SPRITE_COUNT" -gt 0 ]; then
    assert_file_exists "TMNT sprite pack includes source manifest" "$TMNT_SPRITES_DIR/manifest.json"
    TMNT_THEME_SPRITES=$(jq -r '
      [.stages[].sprite, .stages[].shade_sprites[]?, .blocked.sprite, .review.sprite, .done.sprite, .idle.sprite, .error.sprite, .context_alerts[].sprite?]
      | unique
      | map(select(. != ""))
      | sort
      | join(",")
    ' "$ROOT_DIR/themes/tmnt/theme.json")
    TMNT_FILE_SPRITES=$(find "$TMNT_SPRITES_DIR" -maxdepth 1 -type f -name 'tmnt-*.png' -exec basename {} .png \; | sort | paste -sd ',' -)
    assert_eq "TMNT sprite pack covers every themed stage/lifecycle sprite" \
        "$TMNT_THEME_SPRITES" \
        "$TMNT_FILE_SPRITES"
    assert_eq "TMNT sprite manifest records provenance for every shipped sprite" \
        "$TMNT_FILE_SPRITES" \
        "$(jq -r '.sprites | keys | sort | join(",")' "$TMNT_SPRITES_DIR/manifest.json")"
    TMNT_STAGE_SPRITES=$(jq -r '
      [.stages[].sprite, .stages[].shade_sprites[]?]
      | unique
      | map(select(. != ""))
      | sort
      | join(",")
    ' "$ROOT_DIR/themes/tmnt/theme.json")
    assert_eq "TMNT stage and shade sprites are focused compositions" \
        "$TMNT_STAGE_SPRITES" \
        "$(jq -r --arg sprites "$TMNT_STAGE_SPRITES" '
          ($sprites | split(",")) as $wanted
          | [.sprites | to_entries[] | select(
              ((.value.composition // "") == "character-focused")
              and (.key as $key | $wanted | index($key))
            ) | .key]
          | sort
          | join(",")
        ' "$TMNT_SPRITES_DIR/manifest.json")"
    assert_contains "TMNT pizza asset comes from TMNT source provenance" \
        "Teenage Mutant Ninja Turtles" \
        "$(jq -r '.sprites["tmnt-pizza"].source_label' "$TMNT_SPRITES_DIR/manifest.json")"
    assert_eq "TMNT April sprite is marked character-focused" \
        "character-focused" \
        "$(jq -r '.sprites["tmnt-april"].composition // ""' "$TMNT_SPRITES_DIR/manifest.json")"
    assert_contains "TMNT April source is not generic cover art" \
        "character" \
        "$(jq -r '.sprites["tmnt-april"].source_label' "$TMNT_SPRITES_DIR/manifest.json")"
    assert_eq "TMNT April yellow sprites are not gray-matte dominated" \
        "ok" \
        "$(python3 - "$TMNT_SPRITES_DIR" <<'PY'
from pathlib import Path
from PIL import Image
import sys

sprites_dir = Path(sys.argv[1])
failures = []
for sprite in ("tmnt-april", "tmnt-april-yellow-2", "tmnt-april-yellow-3"):
    with Image.open(sprites_dir / f"{sprite}.png").convert("RGBA") as image:
        gray = 0
        yellow = 0
        pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
        for red, green, blue, alpha in pixels:
            if alpha <= 16:
                continue
            if abs(red - green) <= 16 and abs(green - blue) <= 16 and 55 <= red <= 230:
                gray += 1
            if red >= 140 and green >= 110 and blue <= 140 and red >= green - 30:
                yellow += 1
        if yellow <= gray:
            failures.append(f"{sprite}:yellow={yellow}:gray={gray}")

print("ok" if not failures else ",".join(failures))
PY
)"
    assert_eq "TMNT April yellow sprites render yellow-family backdrops" \
        "ok" \
        "$(python3 - "$TMNT_SPRITES_DIR" <<'PY'
from pathlib import Path
from PIL import Image
import sys

sprites_dir = Path(sys.argv[1])
failures = []
for sprite in ("tmnt-april", "tmnt-april-yellow-2", "tmnt-april-yellow-3"):
    with Image.open(sprites_dir / f"{sprite}.png").convert("RGBA") as image:
        red, green, blue, alpha = image.getpixel((0, 0))
        if not (alpha >= 240 and red >= 120 and green >= 95 and blue <= 95 and red >= green):
            failures.append(f"{sprite}:corner={red}-{green}-{blue}-{alpha}")

print("ok" if not failures else ",".join(failures))
PY
)"
    assert_eq "TMNT Shredder sprite is marked character-focused" \
        "character-focused" \
        "$(jq -r '.sprites["tmnt-shredder"].composition // ""' "$TMNT_SPRITES_DIR/manifest.json")"
    assert_contains "TMNT Shredder source is not generic box art" \
        "character" \
        "$(jq -r '.sprites["tmnt-shredder"].source_label' "$TMNT_SPRITES_DIR/manifest.json")"
else
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    printf "  PASS: No unproven TMNT sprite assets are shipped\n"
fi
echo ""

# --- TEST 26: Context/token usage creates a separate ambient alert ---
echo "--- Test 26: Context usage creates ambient alert ---"
cleanup
TMP_CONTEXT_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-context-test.XXXXXX")
TTY_LOG="$TMP_CONTEXT_ROOT/tty.log"
export VISUALHUD_TTY="$TTY_LOG"
export VISUALHUD_THEME="tmnt"

run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test", "info": {"last_token_usage": {"total_tokens": 183000}, "model_context_window": 258400}}'
assert_eq "70% context writes warning state" "warning:70" "$(cat "$CONTEXT_FILE" 2>/dev/null)"
assert_contains "Warning title includes context percent" "CTX 70%" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "Warning user var is emitted" "hudContext" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '5' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test", "info": {"last_token_usage": {"total_tokens": 183000}, "model_context_window": 258400}}'
assert_eq "TMNT warning context keeps Donatello sprite progression" "tmnt-donatello" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "TMNT warning context keeps Donatello purple background tint" "SetColors=bg=2d184c" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "TMNT warning context still labels token pressure" "Mutagen Leak CTX 70%" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '5' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test", "info": {"last_token_usage": {"total_tokens": 220000}, "model_context_window": 258400}}'
assert_eq "85% context writes critical state" "critical:85" "$(cat "$CONTEXT_FILE" 2>/dev/null)"
assert_contains "Critical title includes context percent" "CTX 85%" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "TMNT critical context uses Casey Jones identity" "Casey Jones CTX 85%" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_eq "TMNT critical context keeps Donatello sprite progression" "tmnt-donatello" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "TMNT critical context keeps Donatello purple background tint" "SetColors=bg=2d184c" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_not_contains "TMNT critical context does not gray-wash the pane" "SetColors=bg=494949" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test", "info": {"last_token_usage": {"total_tokens": 129000}, "model_context_window": 258400}}'
assert_file_not_exists "Low context clears ambient alert" "$CONTEXT_FILE"

export VISUALHUD_THEME="pokemon"
: > "$TTY_LOG"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test", "info": {"last_token_usage": {"total_tokens": 183000}, "model_context_window": 258400}}'
assert_eq "Pokemon 70% context writes warning state" "warning:70" "$(cat "$CONTEXT_FILE" 2>/dev/null)"
assert_contains "Pokemon warning context goes to Pokemon Center" "Pokemon Center CTX 70%" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test", "info": {"last_token_usage": {"total_tokens": 220000}, "model_context_window": 258400}}'
assert_eq "Pokemon 85% context writes critical state" "critical:85" "$(cat "$CONTEXT_FILE" 2>/dev/null)"
assert_contains "Pokemon critical context uses Nurse Joy identity" "Nurse Joy CTX 85%" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_eq "Pokemon critical context color is Pokemon Center pink-white" \
    "255-225-235" \
    "$(jq -r '.context_alerts.critical.color | join("-")' "$ROOT_DIR/themes/pokemon/theme.json")"

export VISUALHUD_THEME="tmnt"

CODEX_SESSION_FIXTURE="$TMP_CONTEXT_ROOT/rollout-2026-04-26T00-00-00-codex-session.jsonl"
cat > "$CODEX_SESSION_FIXTURE" <<'JSONL'
{"timestamp":"2026-04-26T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":230000},"model_context_window":258400}}}
JSONL
: > "$TTY_LOG"
export VISUALHUD_CODEX_SESSION_FILE="$CODEX_SESSION_FIXTURE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "codex-session"}'
assert_eq "Codex session token_count fixture writes critical state" "critical:89" "$(cat "$CONTEXT_FILE" 2>/dev/null)"
assert_contains "Codex session token_count fixture appears in title" "CTX 89%" "$(cat "$TTY_LOG" 2>/dev/null)"

unset VISUALHUD_CODEX_SESSION_FILE
CODEX_HOME_FIXTURE="$TMP_CONTEXT_ROOT/codex-home"
mkdir -p "$CODEX_HOME_FIXTURE/sessions/2026/04/26"
CODEX_MATCHING_SESSION="$CODEX_HOME_FIXTURE/sessions/2026/04/26/rollout-2026-04-26T00-00-00-actual-session.jsonl"
cat > "$CODEX_MATCHING_SESSION" <<'JSONL'
{"timestamp":"2026-04-26T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":200000},"model_context_window":258400}}}
JSONL
: > "$TTY_LOG"
export CODEX_HOME="$CODEX_HOME_FIXTURE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "actual-session"}'
assert_eq "Codex session id discovers matching token_count file" "warning:77" "$(cat "$CONTEXT_FILE" 2>/dev/null)"
assert_contains "Discovered Codex token_count file appears in title" "CTX 77%" "$(cat "$TTY_LOG" 2>/dev/null)"

rm -rf "$TMP_CONTEXT_ROOT"
cleanup
echo ""

# --- TEST 27: TMNT source-backed importer crops character-select panels ---
echo "--- Test 27: TMNT source importer creates manifest-backed sprites ---"
cleanup
TMP_IMPORT_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-tmnt-import.XXXXXX")
TMNT_SOURCE="$TMP_IMPORT_ROOT/tmnt-reference.png"
TMNT_OUTPUT="$TMP_IMPORT_ROOT/sprites"
TMNT_SINGLE_SOURCE="$TMP_IMPORT_ROOT/tmnt-single-source.png"
TMNT_MATTE_SOURCE="$TMP_IMPORT_ROOT/tmnt-gray-matte-source.png"
TMNT_MATTE_OUTPUT="$TMP_IMPORT_ROOT/matte-sprites"

python3 - "$TMNT_SOURCE" <<'PY'
from PIL import Image, ImageDraw
import sys

out = sys.argv[1]
image = Image.new("RGB", (800, 420), (0, 0, 0))
draw = ImageDraw.Draw(image)
colors = [(25, 105, 255), (255, 125, 25), (150, 80, 255), (255, 55, 55)]
for idx, color in enumerate(colors):
    left = 30 + idx * 190
    draw.rectangle((left, 20, left + 140, 280), fill=color)
    draw.rectangle((left + 45, 80, left + 95, 220), fill=(20, 150, 60))
draw.rectangle((40, 350, 150, 380), fill=(240, 240, 240))
image.save(out)
PY

python3 - "$TMNT_SINGLE_SOURCE" <<'PY'
from PIL import Image, ImageDraw
import sys

out = sys.argv[1]
image = Image.new("RGB", (320, 240), (255, 210, 60))
draw = ImageDraw.Draw(image)
draw.rectangle((70, 50, 250, 190), fill=(30, 160, 70))
draw.ellipse((110, 75, 210, 175), fill=(255, 90, 40))
image.save(out)
PY

python3 - "$TMNT_MATTE_SOURCE" <<'PY'
from PIL import Image, ImageDraw
import sys

out = sys.argv[1]
image = Image.new("RGB", (280, 420), (164, 172, 180))
draw = ImageDraw.Draw(image)
draw.ellipse((80, 40, 200, 160), fill=(236, 190, 80))
draw.rectangle((100, 150, 180, 360), fill=(246, 210, 70))
draw.rectangle((118, 78, 162, 130), fill=(210, 120, 60))
image.save(out)
PY

python3 "$ROOT_DIR/scripts/import-tmnt-sprites.py" \
    --source "$TMNT_SOURCE" \
    --output-dir "$TMNT_OUTPUT" \
    --source-label "synthetic-character-select"

python3 "$ROOT_DIR/scripts/import-tmnt-sprites.py" \
    --asset "tmnt-pizza=$TMNT_SINGLE_SOURCE" \
    --output-dir "$TMNT_OUTPUT" \
    --source-label "synthetic-single-source"

python3 "$ROOT_DIR/scripts/import-tmnt-sprites.py" \
    --asset-crop "tmnt-shredder=$TMNT_SINGLE_SOURCE=40,30,250,220" \
    --output-dir "$TMNT_OUTPUT" \
    --source-label "synthetic-character-crop"

python3 "$ROOT_DIR/scripts/import-tmnt-sprites.py" \
    --asset-crop "tmnt-april=$TMNT_MATTE_SOURCE=0,0,280,420" \
    --output-dir "$TMNT_MATTE_OUTPUT" \
    --source-label "synthetic-character-matte"

assert_file_exists "Importer writes Leonardo sprite" "$TMNT_OUTPUT/tmnt-leonardo.png"
assert_file_exists "Importer writes Michelangelo sprite" "$TMNT_OUTPUT/tmnt-michelangelo.png"
assert_file_exists "Importer writes Donatello sprite" "$TMNT_OUTPUT/tmnt-donatello.png"
assert_file_exists "Importer writes Raphael sprite" "$TMNT_OUTPUT/tmnt-raphael.png"
assert_file_exists "Importer writes single-source sprite" "$TMNT_OUTPUT/tmnt-pizza.png"
assert_file_exists "Importer writes cropped character sprite" "$TMNT_OUTPUT/tmnt-shredder.png"
assert_file_exists "Importer writes source manifest" "$TMNT_OUTPUT/manifest.json"
assert_eq "Importer manifest marks sprites as source-backed" \
    "tmnt-donatello:synthetic-character-select,tmnt-leonardo:synthetic-character-select,tmnt-michelangelo:synthetic-character-select,tmnt-pizza:synthetic-single-source,tmnt-raphael:synthetic-character-select,tmnt-shredder:synthetic-character-crop" \
    "$(jq -r '[.sprites | to_entries | sort_by(.key)[] | "\(.key):\(.value.source_label)"] | join(",")' "$TMNT_OUTPUT/manifest.json")"
assert_eq "Importer outputs six source-backed sprites" \
    "6" \
    "$(find "$TMNT_OUTPUT" -maxdepth 1 -type f -name 'tmnt-*.png' | wc -l | tr -d ' ')"
assert_eq "Importer stores explicit character crop coordinates" \
    "40,30,250,220" \
    "$(jq -r '.sprites["tmnt-shredder"].crop | join(",")' "$TMNT_OUTPUT/manifest.json")"
assert_eq "Importer marks explicit crop assets as character-focused" \
    "character-focused" \
    "$(jq -r '.sprites["tmnt-shredder"].composition // ""' "$TMNT_OUTPUT/manifest.json")"
assert_eq "Importer ignores footer content outside select panels" \
    "281" \
    "$(jq -r '.sprites["tmnt-leonardo"].crop[3]' "$TMNT_OUTPUT/manifest.json")"
assert_eq "Importer renders terminal-shaped HUD backdrops" \
    "900x1400" \
    "$(python3 - "$TMNT_OUTPUT/tmnt-leonardo.png" <<'PY'
from PIL import Image
import sys

with Image.open(sys.argv[1]) as image:
    print(f"{image.size[0]}x{image.size[1]}")
PY
)"
assert_eq "Importer upscales character art instead of tiny sticker overlay" \
    "large" \
    "$(python3 - "$TMNT_OUTPUT/tmnt-leonardo.png" <<'PY'
from PIL import Image
import sys

with Image.open(sys.argv[1]).convert("RGBA") as image:
    green_pixels = 0
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha > 240 and red < 70 and green > 120 and blue < 100:
                green_pixels += 1
print("large" if green_pixels > 50000 else f"small:{green_pixels}")
PY
)"
assert_eq "Importer strips neutral character matte before rendering" \
    "yellow-dominant" \
    "$(python3 - "$TMNT_MATTE_OUTPUT/tmnt-april.png" <<'PY'
from PIL import Image
import sys

with Image.open(sys.argv[1]).convert("RGBA") as image:
    gray = 0
    yellow = 0
    pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    for red, green, blue, alpha in pixels:
        if alpha <= 16:
            continue
        if abs(red - green) <= 16 and abs(green - blue) <= 16 and 55 <= red <= 230:
            gray += 1
        if red >= 140 and green >= 110 and blue <= 140 and red >= green - 30:
            yellow += 1
print("yellow-dominant" if yellow > gray else f"gray-dominant:{yellow}:{gray}")
PY
)"

rm -rf "$TMP_IMPORT_ROOT"
cleanup
echo ""

# --- TEST 28: TMNT visual smoke sheet covers every color/state ---
echo "--- Test 28: TMNT visual smoke sheet covers every color/state ---"
cleanup
TMP_VISUAL_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-visual-smoke.XXXXXX")
TMNT_CONTACT_SHEET="$TMP_VISUAL_ROOT/tmnt-contact-sheet.png"
TMNT_CONTACT_REPORT="$TMP_VISUAL_ROOT/tmnt-contact-sheet.json"

python3 "$ROOT_DIR/scripts/render-theme-contact-sheet.py" \
    --theme "$ROOT_DIR/themes/tmnt/theme.json" \
    --sprites-dir "$ROOT_DIR/themes/tmnt/sprites" \
    --output "$TMNT_CONTACT_SHEET" \
    --report "$TMNT_CONTACT_REPORT"

assert_file_exists "Visual smoke writes contact sheet" "$TMNT_CONTACT_SHEET"
assert_file_exists "Visual smoke writes machine-readable report" "$TMNT_CONTACT_REPORT"
assert_eq "Visual smoke includes every TMNT stage/lifecycle/context state" \
    "39" \
    "$(jq -r '.entries | length' "$TMNT_CONTACT_REPORT")"
assert_eq "Visual smoke has no missing sprite art for sprite-backed states" \
    "" \
    "$(jq -r '.missing_sprites | join(",")' "$TMNT_CONTACT_REPORT")"
assert_contains "Visual smoke covers yellow April state" \
    "stage:April:tmnt-april:255-220-45" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"
assert_contains "Visual smoke covers Pizza Party with green completion color" \
    "done:Pizza Party:tmnt-pizza:20-185-85" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"
assert_contains "Visual smoke covers Splinter review state" \
    "review:Splinter Review:tmnt-splinter:130-95-65" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"
assert_not_contains "Visual smoke does not render Pizza Party as April yellow" \
    "done:Pizza Party:tmnt-pizza:255-205-75" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"
assert_contains "Visual smoke covers white Casey context state" \
    "context:Casey Jones:tmnt-casey-jones:245-245-245" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"
assert_contains "Visual smoke covers mutagen leak context sprite" \
    "context:Mutagen Leak:tmnt-mutagen:40-220-90" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"
assert_contains "Visual smoke covers Michelangelo orange shade variant" \
    "stage-shade:Michelangelo shade 2:tmnt-michelangelo-orange-2:255-150-48" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"
assert_contains "Visual smoke covers Donatello purple shade variant" \
    "stage-shade:Donatello shade 3:tmnt-donatello-purple-3:125-60-220" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"
assert_contains "Visual smoke covers April yellow shade variant" \
    "stage-shade:April shade 2:tmnt-april-yellow-2:255-235-90" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"
assert_contains "Visual smoke covers Raphael red shade variant" \
    "stage-shade:Raphael shade 2:tmnt-raphael-red-2:235-45-45" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"
assert_contains "Visual smoke covers Raphael hot red shade variant" \
    "stage-shade:Raphael shade 3:tmnt-raphael-red-3:255-80-65" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$TMNT_CONTACT_REPORT")"

rm -rf "$TMP_VISUAL_ROOT"
cleanup
echo ""

# --- TEST 29: Terminal surface palette follows active stage color ---
echo "--- Test 29: Terminal surface palette follows active stage color ---"
cleanup
TMP_SURFACE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-surface.XXXXXX")
TTY_LOG="$TMP_SURFACE_ROOT/tty.log"
export VISUALHUD_TTY="$TTY_LOG"
export VISUALHUD_THEME="tmnt"

printf '5' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Surface palette stage uses Donatello" "tmnt-donatello" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Surface palette sets default background tint" "SetColors=bg=2d184c" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "Surface palette sets selection background tint" "SetColors=selbg=2d184c" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "Surface palette sets tab color through SetColors" "SetColors=tab=9650ff" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "Surface palette sets normal black UI surface tint" "SetColors=black=2d184c" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "Surface palette sets bright black UI surface tint" "SetColors=br_black=2d184c" "$(cat "$TTY_LOG" 2>/dev/null)"

rm -rf "$TMP_SURFACE_ROOT"
cleanup
echo ""

# --- TEST 30: TMNT stage color shades advance within a character band ---
echo "--- Test 30: TMNT stage color shades advance within a character band ---"
cleanup
TMP_SHADE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-shades.XXXXXX")
TTY_LOG="$TMP_SHADE_ROOT/tty.log"
export VISUALHUD_TTY="$TTY_LOG"
export VISUALHUD_THEME="tmnt"

printf '2' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Michelangelo shade step 1 keeps Michelangelo sprite" "tmnt-michelangelo" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Michelangelo shade step 1 is orange base" "SetColors=tab=ff7d19" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '3' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Michelangelo shade step 2 uses orange variant sprite" "tmnt-michelangelo-orange-2" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Michelangelo shade step 2 brightens orange" "SetColors=tab=ff9630" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '4' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Michelangelo shade step 3 uses orange variant sprite" "tmnt-michelangelo-orange-3" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Michelangelo shade step 3 reaches gold orange" "SetColors=tab=ffaf46" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '12' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Raphael shade step 1 uses base Raphael sprite" "tmnt-raphael" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Raphael shade step 1 is base red" "SetColors=tab=ff3737" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '17' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Raphael shade step 2 uses red variant sprite" "tmnt-raphael-red-2" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Raphael shade step 2 deepens red" "SetColors=tab=eb2d2d" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '21' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
assert_eq "Raphael shade step 3 uses red variant sprite" "tmnt-raphael-red-3" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Raphael shade step 3 reaches hot red" "SetColors=tab=ff5041" "$(cat "$TTY_LOG" 2>/dev/null)"

rm -rf "$TMP_SHADE_ROOT"
cleanup
echo ""

# --- TEST 31: Terminal title/colors can reapply after TUI repaint ---
echo "--- Test 31: Terminal title/colors can reapply after TUI repaint ---"
cleanup
TMP_REAPPLY_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-reapply.XXXXXX")
TTY_LOG="$TMP_REAPPLY_ROOT/tty.log"
export VISUALHUD_TTY="$TTY_LOG"
export VISUALHUD_THEME="tmnt"
export VISUALHUD_REAPPLY_DELAY="0.05"

run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}'
sleep 0.15
assert_eq "Delayed reapply emits hudProgress twice" \
    "2" \
    "$(grep -ao 'SetUserVar=hudProgress' "$TTY_LOG" | wc -l | tr -d ' ')"
assert_eq "Delayed reapply emits tab color twice" \
    "2" \
    "$(grep -ao 'SetColors=tab=1969ff' "$TTY_LOG" | wc -l | tr -d ' ')"

rm -rf "$TMP_REAPPLY_ROOT"
cleanup
echo ""

# ============================================================
# Cleanup
cleanup

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
