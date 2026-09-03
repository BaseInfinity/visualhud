#!/bin/bash
# Regression test: journey progression for realistic SDLC workflows.
#
# Fires real Claude hook payloads through the adapter+engine pipeline
# and verifies the journey advances through correct stages for both
# codex-default (6-stage) and sdlc (12-stage) profiles.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-sdlc-journey.XXXXXX")"
DEMO="$TMP/demo"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

PASS=0
FAIL=0
TOTAL=0

check() {
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

check_not() {
    local label="$1" unexpected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$unexpected" != "$actual" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (should NOT be '%s')\n" "$label" "$unexpected"
    fi
}

# Set up isolated demo repo with VisualHUD installed
mkdir -p "$DEMO"
git -C "$DEMO" init -q
printf '{"name":"sdlc-demo"}\n' > "$DEMO/package.json"
git -C "$DEMO" add . && git -C "$DEMO" commit -q -m "init"

FAKE_BIN="$TMP/fake-bin"
mkdir -p "$FAKE_BIN"
printf '#!/bin/bash\nexit 0\n' > "$FAKE_BIN/defaults"
printf '#!/bin/bash\nexit 1\n' > "$FAKE_BIN/pgrep"
chmod +x "$FAKE_BIN/defaults" "$FAKE_BIN/pgrep"

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/visualhud" install claude --target "$DEMO" --platform macos >/dev/null 2>&1 || true

HOOK="$DEMO/.visualhud/.claude/hooks/visualhud-claude.sh"
[ -f "$HOOK" ] || { echo "FAIL: hook not installed"; exit 1; }

CAPTURE="$TMP/capture"

fire() {
    local payload="$1" profile="$2" state_dir="$3"
    rm -f "$CAPTURE"
    printf '%s' "$payload" | \
        CLAUDE_PROJECT_DIR="$DEMO" \
        VISUALHUD_THEME="pokemon" \
        VISUALHUD_STATE_DIR="$state_dir" \
        VISUALHUD_REAPPLY_DELAY=0 \
        VISUALHUD_TTY="$CAPTURE" \
        VISUALHUD_JOURNEY_PROFILE="$profile" \
        bash "$HOOK" >/dev/null 2>/dev/null || true
}

get_title() {
    [ -f "$CAPTURE" ] || { echo ""; return; }
    # hudProgress=<base64>\x07 — extract base64 between = and BEL (0x07)
    local b64
    b64=$(LC_ALL=C sed -n 's/.*hudProgress=\([A-Za-z0-9+/=]*\).*/\1/p' "$CAPTURE" 2>/dev/null | tail -1 || true)
    [ -n "$b64" ] || { echo ""; return; }
    printf '%s' "$b64" | base64 -d 2>/dev/null || echo ""
}

get_checkpoint() {
    local title
    title=$(get_title)
    [ -n "$title" ] || { echo ""; return; }
    # Extract checkpoint name from title like "🟥 1/6 UNDERSTAND 🔥" or "🟥🟧 2/6 PLAN"
    printf '%s' "$title" | sed -E 's/.*[0-9]+\/[0-9]+ ([A-Z_ ]+[A-Z]).*/\1/' || echo ""
}

get_stage_num() {
    local title
    title=$(get_title)
    printf '%s' "$title" | grep -oE '[0-9]+/[0-9]+' | head -1 || echo ""
}

# ===================================================================
echo "=== Test Suite: SDLC Journey Progression ==="
echo ""

# --- codex-default profile (6 stages) ---
echo "--- codex-default (6-stage) ---"
STATE="$TMP/state-codex"
mkdir -p "$STATE"
rm -f "$CAPTURE"

echo "  Phase 0: Intake"
fire '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"README.md"},"session_id":"sdlc"}' \
    codex-default "$STATE"
check "Intake: Read starts at UNDERSTAND" "UNDERSTAND" "$(get_checkpoint)"
check "Intake: Stage 1/6" "1/6" "$(get_stage_num)"

echo "  Phase 1: Plan"
fire '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"src/app.js"},"session_id":"sdlc"}' \
    codex-default "$STATE"
# plan_tool is not a real Claude tool — update_plan doesn't exist in Claude Code
# The journey stays at UNDERSTAND during read-heavy intake
stage_after_reads=$(get_checkpoint)
check "Plan: More reads stay at UNDERSTAND" "UNDERSTAND" "$stage_after_reads"

echo "  Phase 1: Plan review (gpt5-advise plan)"
fire '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"bash scripts/gpt5-advise.sh plan \"implement auth\""},"session_id":"sdlc"}' \
    codex-default "$STATE"
stage_after_plan_review=$(get_checkpoint)
check_not "Plan review should NOT jump to REVIEW" "REVIEW" "$stage_after_plan_review"

echo "  Phase 2: Build (TDD)"
fire '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"tests/test-auth.sh","old_string":"x","new_string":"y"},"session_id":"sdlc"}' \
    codex-default "$STATE"
stage_after_tdd=$(get_checkpoint)
# Edit of test file should map to tdd_red -> implement in codex-default
check "TDD: Edit test file advances to IMPLEMENT" "IMPLEMENT" "$stage_after_tdd"

echo "  Phase 2: Build (code)"
fire '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"src/auth.js","old_string":"a","new_string":"b"},"session_id":"sdlc"}' \
    codex-default "$STATE"
check "Build: Edit code file stays at IMPLEMENT" "IMPLEMENT" "$(get_checkpoint)"

echo "  Phase 3: Test"
fire '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"},"session_id":"sdlc"}' \
    codex-default "$STATE"
stage_after_test=$(get_checkpoint)
check "Test: npm test advances to VERIFY" "VERIFY" "$stage_after_test"

echo "  Phase 4: Review"
fire '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex exec review"},"session_id":"sdlc"}' \
    codex-default "$STATE"
stage_after_review=$(get_checkpoint)
check "Review: codex exec review advances to REVIEW" "REVIEW" "$stage_after_review"

echo "  Phase 5: Done"
fire '{"hook_event_name":"Stop","session_id":"sdlc"}' codex-default "$STATE"
stage_after_stop=$(get_checkpoint)
# Stop after review keeps REVIEW state (review file blocks done transition)
check "Done: Stop after review stays at REVIEW" "REVIEW" "$stage_after_stop"

echo ""

# --- sdlc profile (12 stages) ---
echo "--- sdlc (12-stage) ---"
STATE="$TMP/state-sdlc"
mkdir -p "$STATE"
rm -f "$CAPTURE"

echo "  Phase 0: Intake"
fire '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"README.md"},"session_id":"sdlc2"}' \
    sdlc "$STATE"
check "Intake: Read starts at DISCOVERY" "DISCOVERY" "$(get_checkpoint)"

echo "  Phase 2: Build (TDD)"
fire '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"tests/test-auth.sh","old_string":"x","new_string":"y"},"session_id":"sdlc2"}' \
    sdlc "$STATE"
check "TDD: Edit test file goes to TDD RED" "TDD RED" "$(get_checkpoint)"

echo "  Phase 2: Build (code)"
fire '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"src/auth.js","old_string":"a","new_string":"b"},"session_id":"sdlc2"}' \
    sdlc "$STATE"
check "Build: Edit code file goes to IMPLEMENT" "IMPLEMENT" "$(get_checkpoint)"

echo "  Phase 3: Test (targeted)"
fire '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test -- --filter auth"},"session_id":"sdlc2"}' \
    sdlc "$STATE"
check "Test: npm test --filter goes to TARGETED TEST" "TARGETED TEST" "$(get_checkpoint)"

echo "  Phase 3: Test (full)"
fire '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"bash tests/run-all.sh"},"session_id":"sdlc2"}' \
    sdlc "$STATE"
# run-all should be detected as full_test
stage_full=$(get_checkpoint)
check "Test: run-all goes to FULL TEST" "FULL TEST" "$stage_full"

echo "  Phase 4: Review"
fire '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex exec review"},"session_id":"sdlc2"}' \
    sdlc "$STATE"
check "Review: codex review goes to FINAL REVIEW" "FINAL REVIEW" "$(get_checkpoint)"

echo "  Phase 5: Done (Stop after review)"
fire '{"hook_event_name":"Stop","session_id":"sdlc2"}' sdlc "$STATE"
check "Done: Stop after review stays at FINAL REVIEW" "FINAL REVIEW" "$(get_checkpoint)"

echo ""

# --- Bug regression: plan review should not trigger final_review ---
echo "--- Regression: plan review collision ---"
STATE="$TMP/state-regression"
mkdir -p "$STATE"
rm -f "$CAPTURE"

fire '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"README.md"},"session_id":"reg"}' \
    sdlc "$STATE"
check "Regression setup: starts at DISCOVERY" "DISCOVERY" "$(get_checkpoint)"

fire '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"bash scripts/gpt5-advise.sh plan \"plan summary\""},"session_id":"reg"}' \
    sdlc "$STATE"
stage_plan_review=$(get_checkpoint)
check_not "Regression: gpt5-advise plan should NOT jump to FINAL REVIEW" "FINAL REVIEW" "$stage_plan_review"

echo ""

# --- Bug regression: journey should not bounce backward in codex-default ---
echo "--- Regression: no backward bounce ---"
STATE="$TMP/state-bounce"
mkdir -p "$STATE"
rm -f "$CAPTURE"

# Advance to VERIFY
fire '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"bounce"}' \
    codex-default "$STATE"
fire '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"src/a.js","old_string":"x","new_string":"y"},"session_id":"bounce"}' \
    codex-default "$STATE"
fire '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"},"session_id":"bounce"}' \
    codex-default "$STATE"
check "Bounce setup: at VERIFY" "VERIFY" "$(get_checkpoint)"

# A Read call should NOT move back to UNDERSTAND
fire '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"README.md"},"session_id":"bounce"}' \
    codex-default "$STATE"
check_not "Bounce: Read after VERIFY should NOT go back to UNDERSTAND" "UNDERSTAND" "$(get_checkpoint)"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
