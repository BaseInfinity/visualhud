#!/bin/bash
# Regression tests for the Claude install incident (2026-09-03).
#
# A global install from the home directory replaced all hooks in
# ~/.claude/settings.json with 13 visualhud hooks, breaking every
# Claude Code session. These tests verify 8 safety invariants:
#
#   1. --target install never modifies ~/.claude/settings.json
#   2. --target install from HOME dir still scopes to target
#   3. Hook paths use $CLAUDE_PROJECT_DIR, never absolute paths
#   4. install without --target from non-repo dir errors cleanly
#   5. Merge preserves all pre-existing hooks
#   6. Idempotent: running 3x never duplicates hooks
#   7. Non-hook settings keys (allowedTools, etc.) preserved
#   8. --global install merges, does not replace existing hooks

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/visualhud"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-claude-regression.XXXXXX")"

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

make_repo() {
    local name="$1"
    local target="$TMP_ROOT/$name"
    mkdir -p "$target"
    git -C "$target" init -q
    printf '%s\n' "$target"
}

FAKE_BIN="$TMP_ROOT/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/defaults" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$FAKE_BIN/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$FAKE_BIN/defaults" "$FAKE_BIN/pgrep"
export PATH="$FAKE_BIN:$PATH"

echo "=== Test Suite: Claude install regression (2026-09-03 incident) ==="
echo ""

# ============================================================
# TEST 1: --target install NEVER modifies ~/.claude/settings.json
# This is the exact bug from the incident: running install from $HOME
# replaced all global hooks.
# ============================================================
echo "--- Test 1: --target install never modifies global settings ---"
FAKE_HOME="$TMP_ROOT/home-isolation"
mkdir -p "$FAKE_HOME/.claude"
SENTINEL_SETTINGS='{"model":"opus","hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"bash my-existing-global-hook.sh"}]}]}}'
printf '%s\n' "$SENTINEL_SETTINGS" > "$FAKE_HOME/.claude/settings.json"
GLOBAL_CHECKSUM_BEFORE="$(shasum -a 256 "$FAKE_HOME/.claude/settings.json" | awk '{print $1}')"

target="$(make_repo target-isolation)"
HOME="$FAKE_HOME" "$CLI" install claude --target "$target" --platform macos >/dev/null 2>&1

GLOBAL_CHECKSUM_AFTER="$(shasum -a 256 "$FAKE_HOME/.claude/settings.json" | awk '{print $1}')"
assert_eq "Global settings.json byte-identical after --target install" "$GLOBAL_CHECKSUM_BEFORE" "$GLOBAL_CHECKSUM_AFTER"
assert_eq "Global settings content unchanged" "$SENTINEL_SETTINGS" "$(cat "$FAKE_HOME/.claude/settings.json")"
echo ""

# ============================================================
# TEST 2: --target install with cwd=$HOME still scopes to target
# The original incident ran from $HOME. Ensure that even when cwd
# is the home directory, --target writes only to the target repo.
# ============================================================
echo "--- Test 2: --target install from HOME dir still scopes to target ---"
FAKE_HOME2="$TMP_ROOT/home-cwd-test"
mkdir -p "$FAKE_HOME2/.claude"
printf '%s\n' "$SENTINEL_SETTINGS" > "$FAKE_HOME2/.claude/settings.json"

target="$(make_repo target-from-home)"
pushd "$FAKE_HOME2" >/dev/null
HOME="$FAKE_HOME2" "$CLI" install claude --target "$target" --platform macos >/dev/null 2>&1
popd >/dev/null

assert_eq "Global settings unchanged when install runs from HOME" \
    "$SENTINEL_SETTINGS" "$(cat "$FAKE_HOME2/.claude/settings.json")"
assert_eq "Target repo has its own settings.json" "true" \
    "$([ -f "$target/.claude/settings.json" ] && echo true || echo false)"
echo ""

# ============================================================
# TEST 3: Hook paths use $CLAUDE_PROJECT_DIR, never absolute paths
# Absolute paths in hook commands break when the repo moves or
# when the same settings apply to different worktrees.
# ============================================================
echo "--- Test 3: Hook commands use \$CLAUDE_PROJECT_DIR, not absolute paths ---"
target="$(make_repo path-check)"
"$CLI" install claude --target "$target" --platform macos >/dev/null 2>&1

all_commands="$(jq -r '[.hooks[]?[]?.hooks[]?.command // empty] | .[]' "$target/.claude/settings.json")"
while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    assert_contains "Hook uses CLAUDE_PROJECT_DIR" 'CLAUDE_PROJECT_DIR' "$cmd"
    assert_not_contains "Hook does not contain absolute target path" "$target" "$cmd"
    # Reject any absolute path (starts with /) that isn't inside a $CLAUDE_PROJECT_DIR reference
    stripped=$(printf '%s' "$cmd" | sed "s/\\\$CLAUDE_PROJECT_DIR//g; s/\\\${CLAUDE_PROJECT_DIR[^}]*}//g")
    TOTAL=$((TOTAL + 1))
    if printf '%s' "$stripped" | grep -qE '(^|[[:space:]"])/[a-zA-Z]'; then
        FAIL=$((FAIL + 1))
        printf "  FAIL: Hook contains absolute path outside CLAUDE_PROJECT_DIR: %s\n" "$cmd"
    else
        PASS=$((PASS + 1))
        printf "  PASS: Hook has no stray absolute paths\n"
    fi
done <<< "$all_commands"

wrapper_content="$(cat "$target/.claude/hooks/visualhud-claude.sh")"
assert_contains "Wrapper uses CLAUDE_PROJECT_DIR" 'CLAUDE_PROJECT_DIR' "$wrapper_content"
assert_not_contains "Wrapper does not hardcode absolute repo path" "$target" "$wrapper_content"
echo ""

# ============================================================
# TEST 4: install without --target from a non-repo dir errors cleanly
# Must not fall back to writing hooks globally.
# ============================================================
echo "--- Test 4: install without --target from non-repo dir errors cleanly ---"
NON_REPO="$TMP_ROOT/not-a-repo"
FAKE_HOME3="$TMP_ROOT/home-no-target"
mkdir -p "$NON_REPO" "$FAKE_HOME3/.claude"
printf '%s\n' "$SENTINEL_SETTINGS" > "$FAKE_HOME3/.claude/settings.json"

set +e
pushd "$NON_REPO" >/dev/null
error_output="$(HOME="$FAKE_HOME3" "$CLI" install claude --platform macos 2>&1)"
error_status=$?
popd >/dev/null
set -e

assert_eq "Install without --target from non-repo exits nonzero" "1" "$error_status"
assert_contains "Error message mentions git" "Git" "$error_output"
assert_eq "Global settings untouched after failed install" \
    "$SENTINEL_SETTINGS" "$(cat "$FAKE_HOME3/.claude/settings.json")"
echo ""

# ============================================================
# TEST 5: Merge preserves ALL pre-existing hooks (never replaces)
# The incident replaced the entire hooks object. Verify that every
# pre-existing hook survives, including hooks on events that
# visualhud also registers.
# ============================================================
echo "--- Test 5: Merge preserves all pre-existing hooks ---"
target="$(make_repo merge-preserve)"
mkdir -p "$target/.claude"
cat > "$target/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "^Bash$", "hooks": [ { "type": "command", "command": "bash .claude/hooks/tdd-guard.sh" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash .claude/hooks/sdlc-prompt.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash .claude/hooks/session-log.sh" } ] }
    ],
    "Notification": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "bash .claude/hooks/notify.sh" } ] }
    ],
    "SessionStart": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "bash .claude/hooks/session-init.sh" } ] }
    ]
  }
}
JSON
"$CLI" install claude --target "$target" --platform macos >/dev/null

assert_eq "Pre-existing PreToolUse tdd-guard preserved" "true" \
    "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command == "bash .claude/hooks/tdd-guard.sh")' "$target/.claude/settings.json")"
assert_eq "Pre-existing UserPromptSubmit sdlc-prompt preserved" "true" \
    "$(jq -r 'any(.hooks.UserPromptSubmit[]?.hooks[]?; .command == "bash .claude/hooks/sdlc-prompt.sh")' "$target/.claude/settings.json")"
assert_eq "Pre-existing Stop session-log preserved" "true" \
    "$(jq -r 'any(.hooks.Stop[]?.hooks[]?; .command == "bash .claude/hooks/session-log.sh")' "$target/.claude/settings.json")"
assert_eq "Pre-existing Notification notify preserved" "true" \
    "$(jq -r 'any(.hooks.Notification[]?.hooks[]?; .command == "bash .claude/hooks/notify.sh")' "$target/.claude/settings.json")"
assert_eq "Pre-existing SessionStart session-init preserved" "true" \
    "$(jq -r 'any(.hooks.SessionStart[]?.hooks[]?; .command == "bash .claude/hooks/session-init.sh")' "$target/.claude/settings.json")"
assert_eq "VisualHUD hooks also present alongside existing" "true" \
    "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
echo ""

# ============================================================
# TEST 6: Idempotent — running 3 times never duplicates hooks
# ============================================================
echo "--- Test 6: Three consecutive installs produce no duplicated hooks ---"
target="$(make_repo idempotent)"
"$CLI" install claude --target "$target" --platform macos >/dev/null
"$CLI" install claude --target "$target" --platform macos >/dev/null
"$CLI" install claude --target "$target" --platform macos >/dev/null

for event in PreToolUse Notification UserPromptSubmit Stop StopFailure TaskCompleted CwdChanged SessionStart PreCompact PostCompact SubagentStart SubagentStop PostToolUseFailure; do
    count="$(jq -r "[.hooks.${event}[]?.hooks[]? | select(.command | contains(\"visualhud-claude.sh\"))] | length" "$target/.claude/settings.json")"
    assert_eq "VisualHUD $event hook count is exactly 1 after 3 installs" "1" "$count"
done
echo ""

# ============================================================
# TEST 7: Non-hook settings keys in target are preserved
# The incident destroyed non-hook keys. Verify install preserves them.
# ============================================================
echo "--- Test 7: Non-hook settings keys preserved ---"
target="$(make_repo settings-keys)"
mkdir -p "$target/.claude"
cat > "$target/.claude/settings.json" <<'JSON'
{
  "allowedTools": ["Bash", "Read"],
  "verbosity": "verbose",
  "hooks": {}
}
JSON
"$CLI" install claude --target "$target" --platform macos >/dev/null

assert_eq "allowedTools preserved" '["Bash","Read"]' "$(jq -c '.allowedTools' "$target/.claude/settings.json")"
assert_eq "verbosity preserved" "verbose" "$(jq -r '.verbosity' "$target/.claude/settings.json")"
echo ""

# ============================================================
# TEST 8: --global install merges with existing global hooks
# Specifically: a --global install with pre-existing hooks must
# keep every existing hook AND add its own.
# ============================================================
echo "--- Test 8: --global install merges, does not replace global hooks ---"
FAKE_HOME4="$TMP_ROOT/home-global-merge"
mkdir -p "$FAKE_HOME4/.claude"
cat > "$FAKE_HOME4/.claude/settings.json" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      { "matcher": "^Bash$", "hooks": [ { "type": "command", "command": "/usr/local/bin/my-audit-hook.sh" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "/usr/local/bin/my-submit-check.sh" } ] }
    ]
  }
}
JSON
VISUALHUD_GLOBAL_ROOT="$FAKE_HOME4" "$CLI" install claude --global --platform macos >/dev/null

assert_eq "Global model setting preserved" "opus" "$(jq -r '.model' "$FAKE_HOME4/.claude/settings.json")"
assert_eq "Global audit hook preserved" "true" \
    "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command == "/usr/local/bin/my-audit-hook.sh")' "$FAKE_HOME4/.claude/settings.json")"
assert_eq "Global submit hook preserved" "true" \
    "$(jq -r 'any(.hooks.UserPromptSubmit[]?.hooks[]?; .command == "/usr/local/bin/my-submit-check.sh")' "$FAKE_HOME4/.claude/settings.json")"
assert_eq "VisualHUD hooks added alongside existing" "true" \
    "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$FAKE_HOME4/.claude/settings.json")"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
