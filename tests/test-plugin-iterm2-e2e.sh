#!/bin/bash
# iTerm2 E2E visual verification for the VisualHUD Claude Code PLUGIN hook.
#
# Fires hook events through hooks/visualhud-hook.sh (the plugin entry point)
# and reads rendered terminal state back via the iTerm2 Python API canary.
# Verifies journey advancement, title content, sprites, and cross-project
# state isolation — all through the plugin path (CLAUDE_PLUGIN_ROOT).
#
# Requires: iTerm2 with Python API enabled, iterm2 Python package.
# Skips gracefully when iTerm2 is unavailable.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_HOOK="$ROOT_DIR/hooks/visualhud-hook.sh"
CANARY="$ROOT_DIR/scripts/visualhud-iterm-canary.py"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-plugin-e2e.XXXXXX")"
STATE="$TMP_ROOT/state"
PASS=0
FAIL=0
TOTAL=0

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# --- Preflight: skip if iTerm2/canary unavailable ---

if [ ! -f "$PLUGIN_HOOK" ]; then
    printf "SKIP: plugin hook not found at %s\n" "$PLUGIN_HOOK"
    exit 0
fi

if ! python3 -c "import iterm2" 2>/dev/null; then
    printf "SKIP: iterm2 Python package not available\n"
    exit 0
fi

if [ -z "${ITERM_SESSION_ID:-}" ]; then
    printf "SKIP: not running inside iTerm2 (no ITERM_SESSION_ID)\n"
    exit 0
fi

if ! python3 "$CANARY" probe >/dev/null 2>&1; then
    printf "SKIP: iTerm2 Python API probe failed (API may not be enabled)\n"
    exit 0
fi

# --- Helpers ---

mkdir -p "$STATE"

probe_field() {
    local field="$1"
    python3 "$CANARY" probe 2>/dev/null | python3 -c "
import sys, json, os
d = json.load(sys.stdin)
v = d.get('$field', '')
if '$field' == 'background_image_location' and v:
    v = os.path.basename(v)
print(v)
" 2>/dev/null
}

poll_field() {
    local field="$1" expected="$2" timeout_ms="${3:-5000}"
    local interval_ms=100 elapsed=0 actual=""
    while [ "$elapsed" -lt "$timeout_ms" ]; do
        actual=$(probe_field "$field")
        if [[ "$actual" == *"$expected"* ]]; then
            printf '%s' "$actual"
            return 0
        fi
        sleep 0.1
        elapsed=$((elapsed + interval_ms))
    done
    printf '%s' "$actual"
    return 1
}

fire() {
    local payload="$1" project_dir="$2" theme="${3:-pokemon}"
    printf '%s' "$payload" | \
        CLAUDE_PLUGIN_ROOT="$ROOT_DIR" \
        CLAUDE_PROJECT_DIR="$project_dir" \
        VISUALHUD_THEME="$theme" \
        VISUALHUD_STATE_DIR="$STATE" \
        VISUALHUD_JOURNEY_PROFILE=sdlc \
        VISUALHUD_REAPPLY_DELAY=0 \
        bash "$PLUGIN_HOOK" >/dev/null 2>/dev/null || true
}

check() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf "    PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "    FAIL: %s (expected '%s', got '%s')\n" "$label" "$expected" "$actual"
    fi
}

check_contains() {
    local label="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        printf "    PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "    FAIL: %s (expected '%s' in '%s')\n" "$label" "$needle" "$haystack"
    fi
}

journey_state() {
    local project_dir="$1"
    local project_key
    project_key=$(printf '%s' "$project_dir" | cksum | cut -d' ' -f1)
    local session_key
    session_key=$(printf '%s' "$ITERM_SESSION_ID" | tr ':;/.' '_')
    local journey_key="${session_key}_${project_key}"
    local journey_file="$STATE/visualhud-journey_${journey_key}.json"
    if [ -f "$journey_file" ]; then
        python3 -c "import json,sys; print(json.load(open('$journey_file')).get('current',''))" 2>/dev/null || true
    fi
}

echo "=== Test Suite: Plugin iTerm2 E2E ==="
echo ""

# --- Test 1: Plugin hook fires and renders journey title ---

PROJECT_A="$TMP_ROOT/project-a"
PROJECT_B="$TMP_ROOT/project-b"
mkdir -p "$PROJECT_A" "$PROJECT_B"

echo "--- Test 1: Plugin hook fires and renders journey state ---"

fire '{"hook_event_name":"UserPromptSubmit","session_id":"'"$ITERM_SESSION_ID"'","prompt":"fix it"}' "$PROJECT_A"
title=$(poll_field "hud_progress" "INTAKE" 5000)
check_contains "Plugin hook renders journey title" "INTAKE" "$title"
check "Journey state is intake" "intake" "$(journey_state "$PROJECT_A")"

echo ""

# --- Test 2: Journey advances through plugin hook ---

echo "--- Test 2: Journey advancement via plugin hook ---"

fire '{"hook_event_name":"PreToolUse","session_id":"'"$ITERM_SESSION_ID"'","tool_use_id":"tu_plan_1","journey_checkpoint":"plan","journey_outcome":"started"}' "$PROJECT_A"
title=$(poll_field "hud_progress" "PLAN" 5000)
check_contains "Plan stage renders in title" "PLAN" "$title"
check "Journey state advances to plan" "plan" "$(journey_state "$PROJECT_A")"

fire '{"hook_event_name":"PreToolUse","session_id":"'"$ITERM_SESSION_ID"'","tool_use_id":"tu_impl_1","journey_checkpoint":"implement","journey_outcome":"started"}' "$PROJECT_A"
title=$(poll_field "hud_progress" "IMPLEMENT" 5000)
check_contains "Implement stage renders in title" "IMPLEMENT" "$title"
check "Journey state advances to implement" "implement" "$(journey_state "$PROJECT_A")"

echo ""

# --- Test 3: Cross-project isolation (interleaved) ---
# Pattern: A advances to implement, B starts at intake, A still at implement

echo "--- Test 3: Cross-project isolation (interleaved) ---"

fire '{"hook_event_name":"UserPromptSubmit","session_id":"'"$ITERM_SESSION_ID"'","prompt":"other task"}' "$PROJECT_B"
check "Project B starts at intake" "intake" "$(journey_state "$PROJECT_B")"
check "Project A unchanged at implement" "implement" "$(journey_state "$PROJECT_A")"

fire '{"hook_event_name":"PostToolUse","session_id":"'"$ITERM_SESSION_ID"'","tool_use_id":"tu_impl_1","journey_checkpoint":"implement","journey_outcome":"passed"}' "$PROJECT_A"
check "Project A advances to implemented" "implemented" "$(journey_state "$PROJECT_A")"
check "Project B still at intake" "intake" "$(journey_state "$PROJECT_B")"

echo ""

# --- Test 4: Background sprite via plugin hook ---

echo "--- Test 4: Background sprite applied via plugin hook ---"

fire '{"hook_event_name":"PreToolUse","session_id":"'"$ITERM_SESSION_ID"'","tool_name":"Read"}' "$PROJECT_A" "pokemon"
sprite=$(poll_field "background_image_location" ".png" 5000)
if [ -n "$sprite" ]; then
    check_contains "Pokemon sprite applied" ".png" "$sprite"
else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    printf "    FAIL: No background sprite detected (background images may be disabled)\n"
fi

echo ""

# --- Test 5: Done state via plugin hook ---

echo "--- Test 5: Journey completion via plugin hook ---"

fire '{"hook_event_name":"PostToolUse","session_id":"'"$ITERM_SESSION_ID"'","tool_use_id":"tu_proof_1","journey_checkpoint":"proof","journey_outcome":"passed"}' "$PROJECT_A"
title=$(poll_field "hud_progress" "DONE" 5000)
check_contains "Done state renders in title" "DONE" "$title"
check "Journey state reaches done" "done" "$(journey_state "$PROJECT_A")"

if [ -n "$sprite" ]; then
    done_sprite=$(poll_field "background_image_location" "mew" 5000)
    check_contains "Completion sprite is mew" "mew" "$done_sprite"
fi

echo ""

# --- Test 6: Separate journey state files per project ---

echo "--- Test 6: State file isolation ---"

file_count=$(find "$STATE" -maxdepth 1 -name 'visualhud-journey_*.json' -type f | wc -l | tr -d ' ')
check "Two separate journey state files exist" "2" "$file_count"

echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
