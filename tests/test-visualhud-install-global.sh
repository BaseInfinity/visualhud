#!/bin/bash
# Integration tests for `visualhud install claude --global`.
#
# Fixes the legacy dual-hook race (blue-Charmeleon bug): a global default
# install of the real theme-driven engine.sh, replacing the orphaned
# ~/.claude/hooks/cooking-status.sh. A project-local `install claude --target`
# always takes precedence — the global wrapper yields to it so the two never
# fire against the same session.
#
# VISUALHUD_GLOBAL_ROOT overrides $HOME for the CLI and for generated
# wrappers, so these tests never touch the real ~/.claude.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/visualhud"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-install-global.XXXXXX")"

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
        printf "  FAIL: %s (expected output NOT to contain '%s')\n" "$label" "$needle"
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

assert_executable() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ -x "$filepath" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (not executable: %s)\n" "$label" "$filepath"
    fi
}

echo "=== Test Suite: visualhud install claude --global ==="
echo ""

# --- TEST 1: Global install copies runtime + wraps hook + merges settings ---
echo "--- Test 1: Global install copies runtime, writes wrapper, merges settings ---"
GLOBAL_ROOT="$TMP_ROOT/fake-home-1"
mkdir -p "$GLOBAL_ROOT"
output="$(VISUALHUD_GLOBAL_ROOT="$GLOBAL_ROOT" "$CLI" install claude --global --platform macos 2>&1)"
assert_contains "Global install reports install location" "Installed VisualHUD Claude hooks globally in:" "$output"
assert_contains "Global install reports active theme" "Active theme: pokemon" "$output"
assert_file_exists "Global hook wrapper exists" "$GLOBAL_ROOT/.claude/hooks/visualhud-claude.sh"
assert_executable "Global hook wrapper is executable" "$GLOBAL_ROOT/.claude/hooks/visualhud-claude.sh"
assert_file_exists "Global settings.json exists" "$GLOBAL_ROOT/.claude/settings.json"
assert_file_exists "Global runtime engine copied" "$GLOBAL_ROOT/.visualhud/engine.sh"
assert_file_exists "Pokemon theme ships in global runtime" "$GLOBAL_ROOT/.visualhud/themes/pokemon/theme.json"
assert_eq "Global install defaults to Pokemon" "pokemon" "$(cat "$GLOBAL_ROOT/.visualhud/theme")"
assert_eq "Global PreToolUse VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$GLOBAL_ROOT/.claude/settings.json")"
assert_eq "Global Stop VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.Stop[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$GLOBAL_ROOT/.claude/settings.json")"
echo ""

# --- TEST 2: Global hook command is pinned to the resolved global root, not lazy $CLAUDE_PROJECT_DIR ---
echo "--- Test 2: Global settings hook command is pinned, not lazy \$CLAUDE_PROJECT_DIR ---"
cmd=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("visualhud-claude.sh")) | .command] | first' "$GLOBAL_ROOT/.claude/settings.json")
assert_contains "Global hook command pins the resolved global root path" "$GLOBAL_ROOT/.claude/hooks/visualhud-claude.sh" "$cmd"
assert_not_contains "Global hook command does not rely on lazy CLAUDE_PROJECT_DIR expansion" 'CLAUDE_PROJECT_DIR' "$cmd"
echo ""

# --- TEST 3: Global install preserves existing settings + is idempotent ---
echo "--- Test 3: Global install preserves existing settings + is idempotent ---"
GLOBAL_ROOT2="$TMP_ROOT/fake-home-2"
mkdir -p "$GLOBAL_ROOT2/.claude"
cat > "$GLOBAL_ROOT2/.claude/settings.json" <<'JSON'
{
  "model": "sonnet",
  "hooks": {
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "/some/other/hook.sh" } ] }
    ]
  }
}
JSON
VISUALHUD_GLOBAL_ROOT="$GLOBAL_ROOT2" "$CLI" install claude --global --platform macos >/dev/null
VISUALHUD_GLOBAL_ROOT="$GLOBAL_ROOT2" "$CLI" install claude --global --platform macos >/dev/null
assert_eq "Unrelated existing setting preserved" "sonnet" "$(jq -r '.model' "$GLOBAL_ROOT2/.claude/settings.json")"
assert_eq "Unrelated existing hook preserved" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command == "/some/other/hook.sh")' "$GLOBAL_ROOT2/.claude/settings.json")"
assert_eq "Global VisualHUD PreToolUse hook not duplicated across repeated installs" "1" "$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("visualhud-claude.sh"))] | length' "$GLOBAL_ROOT2/.claude/settings.json")"
echo ""

# --- TEST 4: Global wrapper yields when a project-local install is present ---
echo "--- Test 4: Global wrapper yields when project-local install is present (no double-fire) ---"
GLOBAL_ROOT3="$TMP_ROOT/fake-home-3"
mkdir -p "$GLOBAL_ROOT3"
VISUALHUD_GLOBAL_ROOT="$GLOBAL_ROOT3" "$CLI" install claude --global --platform macos >/dev/null

PROJECT_DIR="$TMP_ROOT/fake-project-with-own-install"
mkdir -p "$PROJECT_DIR/.claude/hooks"
cat > "$PROJECT_DIR/.claude/hooks/visualhud-claude.sh" <<'EOF'
#!/bin/bash
cat > /dev/null
exit 0
EOF
chmod +x "$PROJECT_DIR/.claude/hooks/visualhud-claude.sh"

YIELD_STATE_DIR="$TMP_ROOT/yield-state"
mkdir -p "$YIELD_STATE_DIR"
YIELD_SESSION="w0t0p0:YIELD_TEST_1"
YIELD_STAGE_FILE="$YIELD_STATE_DIR/claude-cooking-stage_$(printf '%s' "$YIELD_SESSION" | tr ':/' '__')"

echo '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}' | \
    CLAUDE_PROJECT_DIR="$PROJECT_DIR" \
    ITERM_SESSION_ID="$YIELD_SESSION" \
    VISUALHUD_STATE_DIR="$YIELD_STATE_DIR" \
    VISUALHUD_TTY=/dev/null \
    bash "$GLOBAL_ROOT3/.claude/hooks/visualhud-claude.sh" > /dev/null 2>&1 || true

assert_file_not_exists "Global wrapper yields: no engine state file written when project install exists" "$YIELD_STAGE_FILE"
echo ""

# --- TEST 5: Global wrapper runs engine.sh normally when no project-local install exists ---
echo "--- Test 5: Global wrapper runs engine.sh when no project-local install is present ---"
NO_PROJECT_DIR="$TMP_ROOT/fake-project-no-install"
mkdir -p "$NO_PROJECT_DIR"

RUN_STATE_DIR="$TMP_ROOT/run-state"
mkdir -p "$RUN_STATE_DIR"
RUN_SESSION="w0t0p0:RUN_TEST_1"
RUN_STAGE_FILE="$RUN_STATE_DIR/claude-cooking-stage_$(printf '%s' "$RUN_SESSION" | tr ':/' '__')"

echo '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}' | \
    CLAUDE_PROJECT_DIR="$NO_PROJECT_DIR" \
    ITERM_SESSION_ID="$RUN_SESSION" \
    VISUALHUD_STATE_DIR="$RUN_STATE_DIR" \
    VISUALHUD_TTY=/dev/null \
    bash "$GLOBAL_ROOT3/.claude/hooks/visualhud-claude.sh" > /dev/null 2>&1 || true

assert_file_exists "Global wrapper runs engine.sh: state file written" "$RUN_STAGE_FILE"
assert_eq "Global wrapper renders stable Pokemon WORKING sprite" "pikachu" "$(cat "$RUN_STAGE_FILE" 2>/dev/null)"
echo ""

# --- TEST 6: Global wrapper does not yield to itself when CLAUDE_PROJECT_DIR is the global root ---
echo "--- Test 6: Global wrapper runs normally when CLAUDE_PROJECT_DIR is the global root itself ---"
SELF_STATE_DIR="$TMP_ROOT/self-state"
mkdir -p "$SELF_STATE_DIR"
SELF_SESSION="w0t0p0:SELF_TEST_1"
SELF_STAGE_FILE="$SELF_STATE_DIR/claude-cooking-stage_$(printf '%s' "$SELF_SESSION" | tr ':/' '__')"

echo '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "test"}' | \
    CLAUDE_PROJECT_DIR="$GLOBAL_ROOT3" \
    ITERM_SESSION_ID="$SELF_SESSION" \
    VISUALHUD_STATE_DIR="$SELF_STATE_DIR" \
    VISUALHUD_TTY=/dev/null \
    bash "$GLOBAL_ROOT3/.claude/hooks/visualhud-claude.sh" > /dev/null 2>&1 || true

assert_file_exists "Global wrapper does not self-yield when run 'in' the global root" "$SELF_STAGE_FILE"
echo ""

# --- TEST 7: --global rejects being combined with --target ---
echo "--- Test 7: --global rejects being combined with --target ---"
set +e
combo_output="$(VISUALHUD_GLOBAL_ROOT="$TMP_ROOT/fake-home-4" "$CLI" install claude --global --target "$TMP_ROOT" --platform macos 2>&1)"
combo_status=$?
set -e
assert_eq "--global + --target exits nonzero" "2" "$combo_status"
assert_contains "--global + --target explains the conflict" "--global" "$combo_output"
echo ""

# ============================================================
echo "=== Results: $PASS/$TOTAL passed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
