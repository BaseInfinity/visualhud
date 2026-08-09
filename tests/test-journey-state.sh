#!/bin/bash
# Integration contract for the reversible Codex task-journey state machine.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ROOT_DIR/engine.sh"
JSON_HELPER="$ROOT_DIR/scripts/visualhud-json.js"
PASS=0
FAIL=0
TOTAL=0
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-journey.XXXXXX")"
STATE_ROOT="$TMP_ROOT/state"
TTY_LOG="$TMP_ROOT/tty.log"
SET_BG_LOG="$TMP_ROOT/set-bg.log"
MOCK_SET_BG="$TMP_ROOT/set_bg.py"
SESSION_ID="journey:test"
SESSION_KEY="journey_test"
PROJECT_CHECKSUM=$(printf '%s' "$ROOT_DIR" | cksum)
PROJECT_KEY=${PROJECT_CHECKSUM%% *}
JOURNEY_KEY="${SESSION_KEY}_${PROJECT_KEY}"
JOURNEY_FILE="$STATE_ROOT/visualhud-journey_${JOURNEY_KEY}.json"
HISTORY_FILE="$STATE_ROOT/visualhud-journey-history_${JOURNEY_KEY}.jsonl"
AGGREGATE_FILE="$STATE_ROOT/visualhud-aggregate_${JOURNEY_KEY}"
OPERATION_DIR="$STATE_ROOT/visualhud-journey-operations_${JOURNEY_KEY}.d"

mkdir -p "$STATE_ROOT"
: > "$TTY_LOG"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$label"
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
        printf '  PASS: %s\n' "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (missing '%s')\n" "$label" "$needle"
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (unexpected '%s')\n" "$label" "$needle"
    fi
}

run_engine() {
    local payload="$1"
    printf '%s' "$payload" | \
        ITERM_SESSION_ID="$SESSION_ID" \
        VISUALHUD_STATE_DIR="$STATE_ROOT" \
        VISUALHUD_TTY="${VISUALHUD_TEST_TTY:-$TTY_LOG}" \
        VISUALHUD_THEMES_DIR="$ROOT_DIR/themes" \
        VISUALHUD_THEME="${VISUALHUD_TEST_THEME:-pokemon}" \
        VISUALHUD_JOURNEY_PROFILE="${VISUALHUD_TEST_PROFILE:-sdlc}" \
        VISUALHUD_ACTIVITY_MODE=semantic \
        VISUALHUD_REAPPLY_DELAY="${VISUALHUD_TEST_REAPPLY_DELAY:-0}" \
        VISUALHUD_TITLE_WIDTH="${VISUALHUD_TEST_TITLE_WIDTH:-}" \
        bash "$ENGINE"
}

journey_state() {
    jq -r '.current' "$JOURNEY_FILE" 2>/dev/null || true
}

echo "=== Test Suite: task journey state machine ==="
echo ""

echo "--- Test 1: Built-in profiles expose explicit ordered checkpoints ---"
assert_eq "Codex default profile is coarse" \
    "understand,plan,implement,verify,review,done" \
    "$(node "$JSON_HELPER" journey-profile codex-default | jq -r '[.[].id] | join(",")')"
assert_eq "SDLC profile includes local proof checkpoints" \
    "intake,discovery,plan,tdd_red,implement,implemented,targeted_test,full_test,self_review,final_review,proof,done" \
    "$(node "$JSON_HELPER" journey-profile sdlc | jq -r '[.[].id] | join(",")')"
assert_eq "Release profile extends SDLC through verified shipping" \
    "intake,discovery,plan,tdd_red,implement,implemented,targeted_test,full_test,self_review,final_review,proof,ci,publish,smoke,done" \
    "$(node "$JSON_HELPER" journey-profile release | jq -r '[.[].id] | join(",")')"
assert_eq "Flag graphemes count as double-width in responsive titles" "fallback" \
    "$(node "$JSON_HELPER" fit-title 4 "🇺🇸🇺🇸X" fallback)"
assert_eq "Keycap graphemes count as double-width in responsive titles" "fallback" \
    "$(node "$JSON_HELPER" fit-title 2 "1️⃣X" fallback)"
echo ""

echo "--- Test 2: Pure transitions move forward, backward, or preserve honestly ---"
assert_eq "Plan evidence advances to planning" "plan" \
    "$(node "$JSON_HELPER" journey-transition sdlc intake plan started | jq -r '.current')"
assert_eq "Successful implementation reaches implemented checkpoint" "implemented" \
    "$(node "$JSON_HELPER" journey-transition sdlc implement implement passed | jq -r '.current')"
assert_eq "Successful targeted tests advance to full suite" "full_test" \
    "$(node "$JSON_HELPER" journey-transition sdlc targeted_test targeted_test passed | jq -r '.current')"
assert_eq "Regression rolls later proof back to implementation" "implement" \
    "$(node "$JSON_HELPER" journey-transition sdlc self_review full_test failed | jq -r '.current')"
assert_eq "Transient CI outage preserves the CI gate" "ci" \
    "$(node "$JSON_HELPER" journey-transition release ci ci transient | jq -r '.current')"
assert_eq "Expected RED evidence remains at the TDD red checkpoint" "tdd_red" \
    "$(node "$JSON_HELPER" journey-transition sdlc implement tdd_red expected_failure | jq -r '.current')"
assert_eq "Coarse profile maps full-suite evidence to verify" "verify" \
    "$(node "$JSON_HELPER" journey-transition codex-default implement full_test started | jq -r '.current')"
assert_eq "Coarse profile maps final-review evidence to review" "review" \
    "$(node "$JSON_HELPER" journey-transition codex-default verify final_review started | jq -r '.current')"
assert_eq "Coarse verification failure rolls back to implementation" "implement" \
    "$(node "$JSON_HELPER" journey-transition codex-default review full_test failed | jq -r '.current')"
assert_eq "Coarse review finding rolls back to implementation" "implement" \
    "$(node "$JSON_HELPER" journey-transition codex-default review final_review finding | jq -r '.current')"
assert_eq "Routine discovery cannot rewind completed implementation" "implemented" \
    "$(node "$JSON_HELPER" journey-transition sdlc implemented discovery started | jq -r '.current')"
assert_eq "Routine plan completion cannot rewind full verification" "full_test" \
    "$(node "$JSON_HELPER" journey-transition sdlc full_test plan passed | jq -r '.current')"
assert_eq "Starting a new implementation invalidates later verification" "implement" \
    "$(node "$JSON_HELPER" journey-transition sdlc full_test implement started | jq -r '.current')"
assert_eq "Starting a new test edit returns to TDD RED" "tdd_red" \
    "$(node "$JSON_HELPER" journey-transition sdlc final_review tdd_red started | jq -r '.current')"
assert_eq "Explicit plan invalidation clears every later checkpoint" "plan" \
    "$(node "$JSON_HELPER" journey-transition sdlc proof plan invalidated | jq -r '.current')"
echo ""

echo "--- Test 3: Engine persists forward progress and transition history ---"
run_engine '{"hook_event_name":"UserPromptSubmit","session_id":"journey:test","prompt":"fix it"}'
assert_eq "Prompt initializes intake" "intake" "$(journey_state)"
: > "$TTY_LOG"
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"plan","journey_outcome":"started"}'
assert_eq "Plan signal advances persistent journey" "plan" "$(journey_state)"
assert_contains "Plan title names the active checkpoint" "PLAN" "$(cat "$TTY_LOG")"
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"implement","journey_outcome":"started"}'
assert_eq "Implementation signal advances persistent journey" "implement" "$(journey_state)"
: > "$TTY_LOG"
run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","journey_checkpoint":"implement","journey_outcome":"passed"}'
assert_eq "Successful implementation advances to implemented" "implemented" "$(journey_state)"
assert_contains "Successful evidence repaints the advanced checkpoint immediately" "IMPLEMENTED" "$(cat "$TTY_LOG")"
assert_eq "Every accepted transition is recorded" "4" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","tool_name":"read"}'
assert_eq "Generic tool activity cannot advance task completion" "implemented" "$(journey_state)"
assert_eq "Journey mode does not create tool-count progress" "absent" "$([ -f "$STATE_ROOT/claude-cooking-counter_${SESSION_KEY}" ] && printf present || printf absent)"
echo ""

echo "--- Test 4: Regression rolls back; overlays and aggregates preserve state ---"
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"full_test","journey_outcome":"started"}'
assert_eq "Full suite becomes current" "full_test" "$(journey_state)"
run_engine '{"hook_event_name":"PostToolUseFailure","session_id":"journey:test","journey_checkpoint":"full_test","journey_outcome":"failed","rollback_activity":false}'
assert_eq "Failed full suite returns to implementation" "implement" "$(journey_state)"
: > "$TTY_LOG"
run_engine '{"hook_event_name":"Notification","notification_type":"permission_prompt","permission_key":"journey-hitl","session_id":"journey:test"}'
assert_eq "HITL overlay preserves underlying journey" "implement" "$(journey_state)"
assert_contains "HITL overlay remains explicit" "HITL" "$(cat "$TTY_LOG")"
run_engine '{"hook_event_name":"PreCompact","session_id":"journey:test"}'
assert_eq "Compaction overlay preserves underlying journey" "implement" "$(journey_state)"
: > "$TTY_LOG"
run_engine '{"hook_event_name":"PostCompact","session_id":"journey:test","journey_aggregate":"Tasks 2/4"}'
assert_eq "Aggregate status cannot move task journey" "implement" "$(journey_state)"
assert_contains "Aggregate status uses a separate terminal variable" "SetUserVar=hudAggregate=VGFza3MgMi80" "$(cat "$TTY_LOG")"
assert_eq "Aggregate status persists for the current task" "Tasks 2/4" "$(cat "$AGGREGATE_FILE")"
echo ""

echo "--- Test 5: Sprite-less journey visuals clear stale character art ---"
cat > "$MOCK_SET_BG" <<'PY'
import os
import sys

with open(os.environ["VISUALHUD_SET_BG_LOG"], "a", encoding="utf-8") as handle:
    if os.path.basename(sys.argv[1] if len(sys.argv) > 1 else "") == os.environ.get("VISUALHUD_TEST_DELAY_SPRITE"):
        import time
        time.sleep(0.3)
    handle.write((sys.argv[1] if len(sys.argv) > 1 else "") + "\n")
PY
export VISUALHUD_SET_BG="$MOCK_SET_BG"
export VISUALHUD_SET_BG_LOG="$SET_BG_LOG"
export VISUALHUD_BG=on
touch "$STATE_ROOT/claude-cooking-bg-clear_${SESSION_KEY}"
VISUALHUD_TEST_TTY=/dev/null VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"implement","journey_outcome":"started"}'
for _ in 1 2 3 4 5; do [ -s "$SET_BG_LOG" ] && break; sleep 0.1; done
assert_contains "Sprite-backed checkpoint sets character art" "/pokemon/sprites/" "$(cat "$SET_BG_LOG" 2>/dev/null)"
VISUALHUD_TEST_TTY=/dev/null run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","journey_checkpoint":"proof","journey_outcome":"passed"}'
for _ in 1 2 3 4 5; do
    grep -q '/pokemon/sprites/mew.png' "$SET_BG_LOG" 2>/dev/null && break
    sleep 0.1
done
assert_contains "DONE applies the matching completion sprite" "/pokemon/sprites/mew.png" "$(cat "$SET_BG_LOG" 2>/dev/null)"
: > "$SET_BG_LOG"
VISUALHUD_TEST_TTY=/dev/null run_engine '{"hook_event_name":"PostCompact","session_id":"journey:test"}'
for _ in 1 2 3 4 5; do [ -s "$SET_BG_LOG" ] && break; sleep 0.1; done
assert_contains "Lifecycle repaint restores the current journey sprite" "/pokemon/sprites/mew.png" "$(cat "$SET_BG_LOG" 2>/dev/null)"
: > "$SET_BG_LOG"
export VISUALHUD_TEST_DELAY_SPRITE=raichu.png
VISUALHUD_TEST_TTY=/dev/null run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"implement","journey_outcome":"started"}'
VISUALHUD_TEST_TTY=/dev/null run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","journey_checkpoint":"proof","journey_outcome":"passed"}'
sleep 0.6
assert_contains "Latest DONE sprite wins over an older slow background update" "/pokemon/sprites/mew.png" "$(tail -n 1 "$SET_BG_LOG" 2>/dev/null)"
unset VISUALHUD_TEST_DELAY_SPRITE
VISUALHUD_TEST_TTY=/dev/null VISUALHUD_TEST_THEME=power-rangers run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"plan","journey_outcome":"started"}'
for _ in 1 2 3 4 5; do
    [ -f "$SET_BG_LOG" ] && [ -z "$(tail -n 1 "$SET_BG_LOG" 2>/dev/null)" ] && break
    sleep 0.1
done
assert_eq "Colors-only checkpoint actively clears stale character art" "" "$(tail -n 1 "$SET_BG_LOG" 2>/dev/null)"
: > "$SET_BG_LOG"
rm -f "$STATE_ROOT/claude-cooking-bg-target_${SESSION_KEY}"
VISUALHUD_TEST_TTY=/dev/null VISUALHUD_TEST_THEME=power-rangers run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"plan","journey_outcome":"started"}'
for _ in 1 2 3 4 5; do [ -s "$SET_BG_LOG" ] && break; sleep 0.1; done
assert_eq "Fresh colors-only state explicitly clears unknown background art" "1" \
    "$(wc -l < "$SET_BG_LOG" | tr -d ' ')"
: > "$SET_BG_LOG"
VISUALHUD_TEST_TTY=/dev/null VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"implement","journey_outcome":"started"}'
for _ in 1 2 3 4 5; do [ -s "$SET_BG_LOG" ] && break; sleep 0.1; done
: > "$SET_BG_LOG"
VISUALHUD_TEST_REAPPLY_DELAY=0.05 VISUALHUD_TEST_TTY=/dev/null VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","tool_name":"read"}'
for _ in 1 2 3 4 5; do [ -s "$SET_BG_LOG" ] && break; sleep 0.1; done
assert_contains "Delayed ordinary hook restores an unchanged journey sprite" "/pokemon/sprites/" "$(cat "$SET_BG_LOG" 2>/dev/null)"
unset VISUALHUD_SET_BG VISUALHUD_SET_BG_LOG VISUALHUD_BG
echo ""

echo "--- Test 6: A completed task resets only when the next task begins ---"
VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"proof","journey_outcome":"started"}'
: > "$TTY_LOG"
VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","journey_checkpoint":"proof","journey_outcome":"passed"}'
assert_eq "Passing the final required gate reaches done" "done" "$(journey_state)"
assert_not_contains "DONE title does not duplicate its completion marker" "⭐ ⭐" "$(cat "$TTY_LOG")"
assert_contains "DONE title prioritizes checkpoint position" "12/12 DONE" "$(cat "$TTY_LOG")"
: > "$TTY_LOG"
VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"UserPromptSubmit","session_id":"journey:test","prompt":"start the next task"}'
assert_eq "Next prompt starts a fresh journey after completion" "intake" "$(journey_state)"
assert_eq "Next prompt clears the completed task aggregate" "absent" "$([ -f "$AGGREGATE_FILE" ] && printf present || printf absent)"
assert_not_contains "Fresh journey does not render the old aggregate" "VGFza3MgMi80" "$(cat "$TTY_LOG")"
echo ""

echo "--- Test 6b: Journey titles are task-first and responsive ---"
rm -f "$JOURNEY_FILE"
: > "$TTY_LOG"
VISUALHUD_TEST_TITLE_WIDTH=120 VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"proof","journey_outcome":"started","journey_aggregate":"Tasks 2/4"}'
assert_contains "Wide title names checkpoint position before metadata" "11/12 PROOF" "$(cat "$TTY_LOG")"
assert_contains "Wide title includes authoritative aggregate" "Tasks 2/4" "$(cat "$TTY_LOG")"
assert_not_contains "Wide title omits redundant character name" "Blastoise" "$(cat "$TTY_LOG")"
: > "$TTY_LOG"
VISUALHUD_TEST_TITLE_WIDTH=61 VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"PostCompact","session_id":"journey:test","journey_aggregate":"Milestone 123456789/123456789"}'
assert_contains "Measured title retains checkpoint at an intermediate width" "11/12 PROOF" "$(cat "$TTY_LOG")"
assert_not_contains "Measured title drops aggregate metadata that does not fit" "Milestone 123456789/123456789" "$(cat "$TTY_LOG")"
: > "$TTY_LOG"
export VISUALHUD_CONTEXT_USED_PERCENT=80
VISUALHUD_TEST_TITLE_WIDTH=61 VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"PostCompact","session_id":"journey:test"}'
assert_contains "Context-aware title retains checkpoint state" "11/12 PROOF" "$(cat "$TTY_LOG")"
assert_contains "Context-aware title retains the active alert" "Pokemon Center CTX 80%" "$(cat "$TTY_LOG")"
assert_not_contains "Context-aware title drops project metadata to fit" "visualhud" "$(cat "$TTY_LOG")"
assert_not_contains "Context-aware title drops progress blocks to fit" "🟥" "$(cat "$TTY_LOG")"
unset VISUALHUD_CONTEXT_USED_PERCENT
: > "$TTY_LOG"
VISUALHUD_TEST_TITLE_WIDTH=33 VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"PostCompact","session_id":"journey:test"}'
assert_contains "Measured narrow title retains checkpoint position" "11/12 PROOF" "$(cat "$TTY_LOG")"
assert_not_contains "Measured narrow title drops a double-width progress track that does not fit" "🟥" "$(cat "$TTY_LOG")"
: > "$TTY_LOG"
VISUALHUD_TEST_TITLE_WIDTH=24 VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"PostCompact","session_id":"journey:test"}'
assert_contains "Narrow title retains checkpoint position and state" "11/12 PROOF" "$(cat "$TTY_LOG")"
assert_not_contains "Narrow title drops project metadata first" "visualhud" "$(cat "$TTY_LOG")"
assert_not_contains "Narrow title drops aggregate metadata before task state" "Tasks 2/4" "$(cat "$TTY_LOG")"
: > "$TTY_LOG"
VISUALHUD_TEST_TITLE_WIDTH=20 VISUALHUD_TEST_THEME=pokemon run_engine '{"hook_event_name":"Notification","notification_type":"permission_prompt","permission_key":"responsive-hitl","session_id":"journey:test"}'
assert_contains "Narrow HITL overlay retains checkpoint position" "11/12 PROOF" "$(cat "$TTY_LOG")"
assert_contains "Narrow HITL overlay retains its semantic label" "HITL" "$(cat "$TTY_LOG")"
assert_not_contains "Narrow HITL overlay drops redundant state prose" "Approval required — visualhud" "$(cat "$TTY_LOG")"
unset VISUALHUD_TEST_TITLE_WIDTH
echo ""

echo "--- Test 7: An active release journey keeps its persisted profile ---"
rm -f "$JOURNEY_FILE"
VISUALHUD_TEST_PROFILE=release run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","journey_checkpoint":"proof","journey_outcome":"passed"}'
assert_eq "Release proof enters CI" "release:ci" \
    "$(jq -r '[.profile,.current] | join(":")' "$JOURNEY_FILE")"
: > "$TTY_LOG"
VISUALHUD_TEST_PROFILE=release run_engine '{"hook_event_name":"JourneyUpdate","session_id":"journey:test","journey_profile":"release","journey_checkpoint":"ci","journey_outcome":"transient"}'
assert_eq "Transient release failure preserves the CI checkpoint" "release:ci" \
    "$(jq -r '[.profile,.current] | join(":")' "$JOURNEY_FILE")"
assert_contains "Transient release failure renders an error overlay" "Error" "$(cat "$TTY_LOG")"
: > "$TTY_LOG"
VISUALHUD_TEST_PROFILE=sdlc run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","tool_name":"read"}'
assert_eq "Ordinary hooks preserve the active release profile" "release:ci" \
    "$(jq -r '[.profile,.current] | join(":")' "$JOURNEY_FILE")"
assert_contains "Persisted release checkpoint renders as CI" "CI" "$(cat "$TTY_LOG")"
assert_not_contains "Persisted release checkpoint does not render as intake" "INTAKE" "$(cat "$TTY_LOG")"
node "$JSON_HELPER" journey-transition release smoke smoke passed > "$JOURNEY_FILE"
VISUALHUD_TEST_PROFILE=sdlc run_engine '{"hook_event_name":"UserPromptSubmit","session_id":"journey:test","prompt":"normal task"}'
assert_eq "New task returns to the requested repo profile" "sdlc:intake" \
    "$(jq -r '[.profile,.current] | join(":")' "$JOURNEY_FILE")"
echo ""

echo "--- Test 8: Explicit journey disablement overrides persisted pane state ---"
node "$JSON_HELPER" journey-transition release proof proof passed > "$JOURNEY_FILE"
: > "$TTY_LOG"
VISUALHUD_TEST_PROFILE=off run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","tool_name":"read"}'
assert_eq "Disabled journey leaves persisted state untouched" "release:ci" \
    "$(jq -r '[.profile,.current] | join(":")' "$JOURNEY_FILE")"
assert_not_contains "Disabled journey does not render the persisted checkpoint" "CI" "$(cat "$TTY_LOG")"
echo ""

echo "--- Test 9: Read-only Codex turns complete when the turn stops ---"
rm -f "$JOURNEY_FILE"
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"UserPromptSubmit","session_id":"journey:test","prompt":"what does this file do?"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"discovery","journey_outcome":"started"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","journey_checkpoint":"discovery","journey_outcome":"passed"}'
assert_eq "Successful discovery reaches coarse planning" "plan" "$(journey_state)"
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"Stop","session_id":"journey:test","last_assistant_message":"The file configures the runtime."}'
assert_eq "Read-only completion reaches done" "done" "$(journey_state)"
rm -f "$JOURNEY_FILE"
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","permission_key":"request:failed-read","journey_checkpoint":"discovery","journey_outcome":"started"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"PostToolUseFailure","session_id":"journey:test","permission_key":"request:failed-read","journey_checkpoint":"discovery","journey_outcome":"failed"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"Stop","session_id":"journey:test","last_assistant_message":"I could not read the file."}'
assert_eq "Failed discovery cannot render task completion" "understand" "$(journey_state)"
rm -f "$JOURNEY_FILE"
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"UserPromptSubmit","session_id":"journey:test","prompt":"query the service"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"Notification","notification_type":"permission_check","permission_key":"request:query","session_id":"journey:test"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"Notification","notification_type":"permission_check","permission_key":"request:query","session_id":"journey:test"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"PostToolUseFailure","permission_key":"request:query","session_id":"journey:test","tool_name":"mcp__db__query"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"PreToolUse","permission_key":"request:query","session_id":"journey:test","tool_name":"mcp__db__fallback"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"Stop","session_id":"journey:test","last_assistant_message":"The query failed."}'
assert_eq "Unclassified tool failure cannot render task completion" "understand" "$(journey_state)"
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"UserPromptSubmit","session_id":"journey:test","prompt":"read the fallback result"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"discovery","journey_outcome":"started"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","journey_checkpoint":"discovery","journey_outcome":"passed"}'
VISUALHUD_TEST_PROFILE=codex-default run_engine '{"hook_event_name":"Stop","session_id":"journey:test","last_assistant_message":"The fallback result is valid."}'
assert_eq "A later successful read-only turn can complete" "done" "$(journey_state)"
echo ""

echo "--- Test 10: Invalidating edits reject stale concurrent completions ---"
rm -f "$JOURNEY_FILE"
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","permission_key":"request:old-suite","journey_checkpoint":"full_test","journey_outcome":"started"}'
assert_eq "Concurrent full suite starts verification" "full_test" "$(journey_state)"
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","permission_key":"request:new-edit","journey_checkpoint":"implement","journey_outcome":"started"}'
assert_eq "New edit invalidates concurrent verification" "implement" "$(journey_state)"
run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","permission_key":"request:old-suite","journey_checkpoint":"full_test","journey_outcome":"passed"}'
assert_eq "Stale full-suite success cannot revalidate edited code" "implement" "$(journey_state)"
run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","permission_key":"request:new-edit","journey_checkpoint":"implement","journey_outcome":"passed"}'
assert_eq "Current-generation edit completion is accepted" "implemented" "$(journey_state)"
rm -f "$JOURNEY_FILE"
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","permission_key":"request:same-suite","journey_checkpoint":"full_test","journey_outcome":"started"}'
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","permission_key":"request:same-suite","journey_checkpoint":"full_test","journey_outcome":"started"}'
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","permission_key":"request:duplicate-edit","journey_checkpoint":"implement","journey_outcome":"started"}'
run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","permission_key":"request:same-suite","journey_checkpoint":"full_test","journey_outcome":"passed"}'
run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","permission_key":"request:same-suite","journey_checkpoint":"full_test","journey_outcome":"passed"}'
assert_eq "Every stale duplicate completion is rejected" "implement" "$(journey_state)"
echo ""

echo "--- Test 10b: Unknown terminal responses retire operation markers ---"
rm -f "$JOURNEY_FILE"
rm -rf "$OPERATION_DIR"
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_operation_key":"request:repeated-suite","journey_checkpoint":"full_test","journey_outcome":"started"}'
run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","journey_operation_key":"request:repeated-suite","journey_terminal":true}'
assert_eq "Unknown terminal response removes the active marker" "0" \
    "$(find "$OPERATION_DIR" -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_operation_key":"request:new-edit","journey_checkpoint":"implement","journey_outcome":"started"}'
run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","journey_operation_key":"request:new-edit","journey_checkpoint":"implement","journey_outcome":"passed"}'
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_operation_key":"request:repeated-suite","journey_checkpoint":"full_test","journey_outcome":"started"}'
run_engine '{"hook_event_name":"PostToolUse","session_id":"journey:test","journey_operation_key":"request:repeated-suite","journey_checkpoint":"full_test","journey_outcome":"passed"}'
assert_eq "A later identical suite can provide fresh evidence" "self_review" "$(journey_state)"
echo ""

echo "--- Test 10c: Codex session startup stays idle until the first prompt ---"
rm -f "$JOURNEY_FILE"
: > "$TTY_LOG"
run_engine '{"hook_event_name":"Stop","source_event":"SessionStart","start_source":"startup","session_id":"journey:test"}'
assert_eq "Session startup does not initialize an active journey" "absent" \
    "$([ -f "$JOURNEY_FILE" ] && printf present || printf absent)"
assert_contains "Session startup renders the idle theme state" "Your turn" "$(cat "$TTY_LOG")"
echo ""

echo "--- Test 10d: Resume and compact starts preserve an in-flight journey ---"
run_engine '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"plan","journey_outcome":"started","journey_aggregate":"Tasks 2/4"}'
run_engine '{"hook_event_name":"Stop","source_event":"SessionStart","start_source":"resume","session_id":"journey:test"}'
assert_eq "Session resume preserves the active checkpoint" "plan" "$(journey_state)"
assert_eq "Session resume preserves aggregate status" "Tasks 2/4" "$(cat "$AGGREGATE_FILE" 2>/dev/null || true)"
run_engine '{"hook_event_name":"Stop","source_event":"SessionStart","start_source":"compact","session_id":"journey:test"}'
assert_eq "Compact restart preserves the active checkpoint" "plan" "$(journey_state)"
assert_eq "Compact restart preserves aggregate status" "Tasks 2/4" "$(cat "$AGGREGATE_FILE" 2>/dev/null || true)"
run_engine '{"hook_event_name":"Stop","source_event":"SessionStart","start_source":"clear","session_id":"journey:test"}'
assert_eq "Session clear resets the active journey" "absent" \
    "$([ -f "$JOURNEY_FILE" ] && printf present || printf absent)"
assert_eq "Session clear resets aggregate status" "absent" \
    "$([ -f "$AGGREGATE_FILE" ] && printf present || printf absent)"
echo ""

echo "--- Test 11: Journey persistence is scoped to pane and repository ---"
repo_a="$TMP_ROOT/repo-a"
repo_b="$TMP_ROOT/repo-b"
repo_state="$TMP_ROOT/repo-state"
mkdir -p "$repo_a" "$repo_b" "$repo_state"
(
    cd "$repo_a"
    printf '%s' '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"plan","journey_outcome":"started"}' | \
        ITERM_SESSION_ID="$SESSION_ID" VISUALHUD_STATE_DIR="$repo_state" \
        VISUALHUD_TTY="$TTY_LOG" VISUALHUD_THEMES_DIR="$ROOT_DIR/themes" \
        VISUALHUD_THEME=pokemon VISUALHUD_JOURNEY_PROFILE=sdlc \
        VISUALHUD_ACTIVITY_MODE=semantic VISUALHUD_REAPPLY_DELAY=0 bash "$ENGINE"
)
(
    cd "$repo_b"
    printf '%s' '{"hook_event_name":"PreToolUse","session_id":"journey:test","journey_checkpoint":"implement","journey_outcome":"started"}' | \
        ITERM_SESSION_ID="$SESSION_ID" VISUALHUD_STATE_DIR="$repo_state" \
        VISUALHUD_TTY="$TTY_LOG" VISUALHUD_THEMES_DIR="$ROOT_DIR/themes" \
        VISUALHUD_THEME=pokemon VISUALHUD_JOURNEY_PROFILE=sdlc \
        VISUALHUD_ACTIVITY_MODE=semantic VISUALHUD_REAPPLY_DELAY=0 bash "$ENGINE"
)
assert_eq "One pane keeps separate state for two repositories" "2" \
    "$(find "$repo_state" -maxdepth 1 -name 'visualhud-journey_journey_test_*.json' | wc -l | tr -d ' ')"
echo ""

echo "--- Test 12: Journey updates use one consolidated JSON operation ---"
JSON_LOG="$TMP_ROOT/json-helper.log"
JSON_WRAPPER="$TMP_ROOT/json-helper.js"
cat > "$JSON_WRAPPER" <<EOF
const fs = require("node:fs");
fs.appendFileSync("$JSON_LOG", process.argv.slice(2).join(" ") + "\n");
require("$JSON_HELPER");
EOF
printf '%s' '{"hook_event_name":"PreToolUse","session_id":"consolidated","journey_checkpoint":"plan","journey_outcome":"started"}' | \
    env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
    VISUALHUD_STATE_DIR="$STATE_ROOT" VISUALHUD_TTY="$TTY_LOG" \
    VISUALHUD_THEMES_DIR="$ROOT_DIR/themes" VISUALHUD_THEME=pokemon \
    VISUALHUD_JOURNEY_PROFILE=sdlc VISUALHUD_ACTIVITY_MODE=semantic \
    VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JSON_HELPER="$JSON_WRAPPER" bash "$ENGINE"
assert_eq "State transition and render use one journey helper call" "1" \
    "$(grep -c '^journey-apply ' "$JSON_LOG" || true)"
assert_eq "Journey signal fields are not parsed through separate Node calls" "0" \
    "$(grep -Ec '^field (journey_checkpoint|journey_outcome|permission_key|generation|current)$' "$JSON_LOG" || true)"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
