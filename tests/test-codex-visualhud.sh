#!/bin/bash
# Integration tests for the Codex -> VisualHUD hook adapter.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="$ROOT_DIR/.codex/hooks/visualhud-codex.sh"
HOOKS_JSON="$ROOT_DIR/.codex/hooks.json"
CONFIG_TOML="$ROOT_DIR/.codex/config.toml"
TMP_DIR="$(mktemp -d)"
ENGINE="$TMP_DIR/cooking-status.sh"
LOG_FILE="$TMP_DIR/events.jsonl"
OUT_FILE="$TMP_DIR/stdout.txt"
STATE_ROOT="$TMP_DIR/state"
mkdir -p "$STATE_ROOT"
export VISUALHUD_STATE_DIR="$STATE_ROOT"
COUNTER_FILE="$STATE_ROOT/claude-cooking-counter_w0t0p0_CODEX_TEST_SESSION"

cleanup() {
    rm -f "$COUNTER_FILE"
    rm -rf "$TMP_DIR"
    unset VISUALHUD_STATE_DIR
}
trap cleanup EXIT

cat > "$ENGINE" <<'EOF'
#!/bin/bash
INPUT=$(cat)
printf '%s' "$INPUT" | jq -c \
  --arg theme "${VISUALHUD_THEME:-}" \
  --arg default_theme "${VISUALHUD_DEFAULT_THEME:-}" \
  --arg reapply_delay "${VISUALHUD_REAPPLY_DELAY:-}" \
  --arg journey_profile "${VISUALHUD_JOURNEY_PROFILE:-}" \
  '. + {visualhud_theme: $theme, visualhud_default_theme: $default_theme, visualhud_reapply_delay: $reapply_delay, visualhud_journey_profile: $journey_profile}' >> "$VISUALHUD_TEST_LOG"
printf 'engine stdout should not leak to Codex hook stdout\n'
EOF
chmod +x "$ENGINE"

export VISUALHUD_ENGINE="$ENGINE"
export VISUALHUD_TEST_LOG="$LOG_FILE"
export ITERM_SESSION_ID="w0t0p0:CODEX_TEST_SESSION"
unset VISUALHUD_THEME VISUALHUD_DEFAULT_THEME
rm -f "$COUNTER_FILE"

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

run_adapter() {
    local payload="$1"
    printf '%s' "$payload" | bash "$ADAPTER"
}

last_event_field() {
    local jq_filter="$1"
    tail -n 1 "$LOG_FILE" | jq -r "$jq_filter"
}

echo "=== Test Suite: visualhud-codex.sh ==="
echo ""

echo "--- Test 1: PreToolUse forwards tool progress ---"
stdout="$(run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","turn_id":"turn-1","tool_name":"Bash","tool_input":{"command":"pwd"}}')"
assert_eq "Adapter keeps stdout empty for Codex hook protocol" "" "$stdout"
assert_eq "Engine receives PreToolUse" "PreToolUse" "$(last_event_field '.hook_event_name')"
assert_eq "Engine receives Codex tool name" "Bash" "$(last_event_field '.tool_name')"
assert_eq "Engine receives session id" "codex-session" "$(last_event_field '.session_id')"
assert_eq "Adapter leaves VISUALHUD_THEME open for repo-local theme file" "" "$(last_event_field '.visualhud_theme')"
assert_eq "Adapter defaults TMNT theme for Codex" "tmnt" "$(last_event_field '.visualhud_default_theme')"
assert_eq "Adapter enables delayed title/color reapply for Codex TUI" "0.12" "$(last_event_field '.visualhud_reapply_delay')"
assert_eq "Adapter selects the SDLC journey when repo evidence exists" "sdlc" "$(last_event_field '.visualhud_journey_profile')"
echo ""

echo "--- Test 2: UserPromptSubmit forwards prompt reset ---"
run_adapter '{"hook_event_name":"UserPromptSubmit","session_id":"codex-session","turn_id":"turn-2","prompt":"build the adapter"}' >"$OUT_FILE"
assert_eq "Prompt reset event is forwarded" "UserPromptSubmit" "$(last_event_field '.hook_event_name')"
assert_eq "Prompt text is preserved" "build the adapter" "$(last_event_field '.prompt')"
echo ""

echo "--- Test 3: PermissionRequest maps to correlated HITL ---"
run_adapter '{"hook_event_name":"PermissionRequest","session_id":"codex-session","turn_id":"turn-3","tool_name":"Bash","tool_input":{"command":"npm install","cwd":"/tmp/project","description":"Codex wants network access"}}' >"$OUT_FILE"
assert_eq "Permission request becomes Notification" "Notification" "$(last_event_field '.hook_event_name')"
assert_eq "Permission request becomes human approval HITL" "permission_prompt" "$(last_event_field '.notification_type')"
assert_eq "Permission description is preserved" "Codex wants network access" "$(last_event_field '.message')"
assert_eq "Permission request carries a correlation key" "true" "$(last_event_field '.permission_key | length > 0')"
assert_eq "Permission request keeps Codex default theme" "tmnt" "$(last_event_field '.visualhud_default_theme')"
permission_key="$(last_event_field '.permission_key')"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","turn_id":"turn-3","tool_name":"Bash","tool_use_id":"call-3","tool_input":{"cwd":"/tmp/project","command":"npm install"}}' >"$OUT_FILE"
assert_eq "PreToolUse reuses the PermissionRequest correlation key" "$permission_key" "$(last_event_field '.permission_key')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","turn_id":"turn-3","tool_name":"Bash","tool_use_id":"call-3","tool_input":{"command":"npm install","cwd":"/tmp/project"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "PostToolUse reuses the PermissionRequest correlation key" "$permission_key" "$(last_event_field '.permission_key')"
echo ""

echo "--- Test 4: Stop forwards done state ---"
run_adapter '{"hook_event_name":"Stop","session_id":"codex-session","turn_id":"turn-4","last_assistant_message":"done"}' >"$OUT_FILE"
assert_eq "Stop event is forwarded" "Stop" "$(last_event_field '.hook_event_name')"
assert_eq "Stop preserves last assistant message" "done" "$(last_event_field '.last_assistant_message')"
assert_eq "Stop keeps Codex default theme" "tmnt" "$(last_event_field '.visualhud_default_theme')"
echo ""

echo "--- Test 5: PostToolUse normalizes explicit Codex tool failures ---"
before_count="$(wc -l < "$LOG_FILE" | tr -d ' ')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Successful PostToolUse is forwarded to clear pending permission checks" "$((before_count + 1))" "$(wc -l < "$LOG_FILE" | tr -d ' ')"
assert_eq "Successful ordinary completion stays PostToolUse" "PostToolUse" "$(last_event_field '.hook_event_name')"
before_count="$((before_count + 1))"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"mcp__example__read","tool_response":{"isError":false,"structuredContent":{"success":false}}}' >"$OUT_FILE"
assert_eq "Successful MCP CallToolResult is forwarded as completion" "$((before_count + 1))" "$(wc -l < "$LOG_FILE" | tr -d ' ')"
assert_eq "Successful MCP application data is not treated as failure" "PostToolUse" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"mcp__example__read","tool_response":{"isError":false,"success":false,"ok":false,"content":[]}}' >"$OUT_FILE"
assert_eq "Explicit MCP protocol success outranks application failure flags" "PostToolUse" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_use_id":"tool-5","tool_response":{"exit_code":1}}' >"$OUT_FILE"
assert_eq "Failed PostToolUse becomes PostToolUseFailure" "PostToolUseFailure" "$(last_event_field '.hook_event_name')"
assert_eq "Failed PostToolUse preserves tool id" "tool-5" "$(last_event_field '.tool_use_id')"
assert_eq "Ordinary failed tool rolls back its optimistic activity count" "true" "$(last_event_field '.rollback_activity')"
assert_eq "Failed PostToolUse keeps Codex default theme" "tmnt" "$(last_event_field '.visualhud_default_theme')"
before_count="$(wc -l < "$LOG_FILE" | tr -d ' ')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_use_id":"tool-5b","tool_response":"Process exited with code 1\n"}' >"$OUT_FILE"
assert_eq "Raw shell output is forwarded without guessing failure" "$((before_count + 1))" "$(wc -l < "$LOG_FILE" | tr -d ' ')"
assert_eq "Raw shell output stays an ordinary completion" "PostToolUse" "$(last_event_field '.hook_event_name')"
echo ""

echo "--- Test 5b: Review completion and failures preserve honest lifecycle state ---"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Successful review PostToolUse completes the review lifecycle" "TaskCompleted" "$(last_event_field '.hook_event_name')"
assert_eq "Review completion records its supported Codex source event" "PostToolUse" "$(last_event_field '.source_event')"
quoted_before_count="$(wc -l < "$LOG_FILE" | tr -d ' ')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted \"Review API & UI\""},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Quoted ampersand emits a new foreground review completion" "$((quoted_before_count + 1))" "$(wc -l < "$LOG_FILE" | tr -d ' ')"
assert_eq "Quoted ampersand does not make a foreground review look detached" "TaskCompleted" "$(last_event_field '.hook_event_name')"
before_count="$(wc -l < "$LOG_FILE" | tr -d ' ')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"tool_response":"review failed with exit code 1"}' >"$OUT_FILE"
assert_eq "Raw review output is forwarded without falsely proving completion" "$((before_count + 1))" "$(wc -l < "$LOG_FILE" | tr -d ' ')"
assert_eq "Raw review output stays an ordinary completion" "PostToolUse" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted || true"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Masked review failure cannot falsely prove completion" "PostToolUse" "$(last_event_field '.hook_event_name')"
assert_eq "Masked review cannot emit passing journey evidence" "absent" \
    "$(last_event_field 'if has("journey_checkpoint") then "present" else "absent" end')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"sh -c '\''codex review --uncommitted &'\''"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Nested detached review cannot falsely prove completion" "PostToolUse" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted > /tmp/review.log 2>&1 &"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Detached review launcher cannot falsely prove completion" "PostToolUse" "$(last_event_field '.hook_event_name')"
assert_eq "Detached review cannot emit passing journey evidence" "absent" \
    "$(last_event_field 'if has("journey_checkpoint") then "present" else "absent" end')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"nohup codex review --uncommitted > /tmp/review.log 2>&1 & echo $!"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Compound detached review cannot falsely prove completion" "PostToolUse" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"(codex review --uncommitted > /tmp/review.log 2>&1 &)"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Subshell detached review cannot falsely prove completion" "PostToolUse" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"nohup sh -c '\''codex review --uncommitted'\'' > /tmp/review.log 2>&1 &"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Quoted shell payload detached review cannot falsely prove completion" "PostToolUse" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted # API & UI"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Ampersand in shell comment does not hide foreground completion" "TaskCompleted" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted > review.txt"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Foreground review with output redirection completes" "TaskCompleted" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex exec -o .reviews/latest-review.md \"Review v1.42.0 before ship\""},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Foreground codex exec review prompt completes" "TaskCompleted" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex -c '\''model_reasoning_effort=high'\'' exec -o .reviews/latest-review.md \"Review v1.42.0 before ship\""},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Codex global options do not hide foreground exec review completion" "TaskCompleted" "$(last_event_field '.hook_event_name')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"tool_response":{"exit_code":1}}' >"$OUT_FILE"
assert_eq "Failed review is still an error event" "PostToolUseFailure" "$(last_event_field '.hook_event_name')"
assert_eq "Failed review does not roll back an unrelated activity count" "false" "$(last_event_field '.rollback_activity')"
assert_eq "Failed review is marked as the review lifecycle failure" "true" "$(last_event_field '.review_failure')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Read","permission_mode":"plan","tool_response":{"exit_code":1}}' >"$OUT_FILE"
assert_eq "Failed plan tool does not roll back an unrelated activity count" "false" "$(last_event_field '.rollback_activity')"
assert_eq "Failed plan tool is not marked as a review failure" "false" "$(last_event_field '.review_failure')"
echo ""

echo "--- Test 6: SessionStart initializes idle state ---"
run_adapter '{"hook_event_name":"SessionStart","session_id":"codex-session","source":"startup"}' >"$OUT_FILE"
assert_eq "SessionStart maps to done state" "Stop" "$(last_event_field '.hook_event_name')"
assert_eq "SessionStart source is preserved" "startup" "$(last_event_field '.start_source')"
assert_eq "SessionStart keeps Codex default theme" "tmnt" "$(last_event_field '.visualhud_default_theme')"
echo ""

echo "--- Test 6b: Codex evidence is normalized into task-journey signals ---"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"update_plan","tool_input":{"plan":[{"step":"Implement feature","status":"in_progress"}]}}' >"$OUT_FILE"
assert_eq "Structured plan starts the plan checkpoint" "plan:started" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch"}}' >"$OUT_FILE"
assert_eq "Patch application starts implementation" "implement:started" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch"},"tool_response":{"success":true}}' >"$OUT_FILE"
assert_eq "Successful patch completes implementation" "implement:passed" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: tests/example.test.js\n@@"}}' >"$OUT_FILE"
assert_eq "Test-only patch starts TDD RED" "tdd_red:started" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: tests/example.test.js\n@@"},"tool_response":{"success":true}}' >"$OUT_FILE"
assert_eq "Successful test-only patch stays in TDD RED" "tdd_red:active" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"bash tests/test-journey-state.sh"}}' >"$OUT_FILE"
assert_eq "Focused test starts targeted verification" "targeted_test:started" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"bash tests/test-journey-state.sh"},"tool_response":{"exit_code":1}}' >"$OUT_FILE"
assert_eq "Failed focused test emits rollback evidence" "targeted_test:failed" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"npm test"}}' >"$OUT_FILE"
assert_eq "Full suite command starts full verification" "full_test:started" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
for command in "npm run test" "npm run-script test" "npm test --" "npm run test --"; do
    run_adapter "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}" >"$OUT_FILE"
    assert_eq "Unfiltered npm suite alias starts full verification: $command" "full_test:started" \
        "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
done
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"npm test -- tests/example.test.js"}}' >"$OUT_FILE"
assert_eq "Filtered npm test starts targeted verification" "targeted_test:started" \
    "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
for command in \
    "npm test -- --help" \
    "npm test -- --listTests" \
    "npm test -- --listTests=true" \
    "npm test -- --showConfig" \
    "npm test -- --showConfig=true"; do
    run_adapter "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}" >"$OUT_FILE"
    assert_eq "Non-executing test command emits no verification evidence: $command" "absent" \
        "$(last_event_field 'if has("journey_checkpoint") then "present" else "absent" end')"
done
for command in \
    "npm test -- --coverage" \
    "npm test -- --listTests=0" \
    "npm test -- --listTests=false" \
    "npm test -- --showConfig=0" \
    "npm test -- --showConfig=false" \
    "npm test > test.log" \
    "npm test && npm run lint"; do
    run_adapter "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}" >"$OUT_FILE"
    assert_eq "Runner-wide full-suite command stays full verification: $command" "full_test:started" \
        "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
done
for command in "CI=1 npm test" "NODE_ENV=test npm test" "env CI=1 npm test"; do
    run_adapter "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}" >"$OUT_FILE"
    assert_eq "Environment-prefixed suite starts full verification: $command" "full_test:started" \
        "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
done
for command in "npm test -- --testPathPattern=journey" "npm test -- --testNamePattern journey" "npm test -- --grep journey" "npm test -- --filter=journey"; do
    run_adapter "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}" >"$OUT_FILE"
    assert_eq "Option-filtered suite stays targeted verification: $command" "targeted_test:started" \
        "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
done
for command in "cat tests/run-all.sh" "sed -n 1,20p tests/run-all.sh" "grep npm tests/run-all.sh"; do
    run_adapter "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}" >"$OUT_FILE"
    assert_eq "Inspecting the suite runner emits no verification evidence: $command" "absent" \
        "$(last_event_field 'if has("journey_checkpoint") then "present" else "absent" end')"
done
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"exec_command","tool_input":{"cmd":"npm test"}}' >"$OUT_FILE"
assert_eq "Exec-command cmd field starts full verification" "full_test:started" \
    "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"functions.exec_command","tool_input":{"cmd":"npm test"}}' >"$OUT_FILE"
assert_eq "Namespaced exec-command starts full verification" "full_test:started" \
    "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"functions.exec_command","tool_input":{"cmd":"codex review --uncommitted"}}' >"$OUT_FILE"
assert_eq "Namespaced exec-command cmd field starts final review" "final_review:started" \
    "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"functions.exec_command","tool_input":{"cmd":"node .codex/hooks/git-guard.cjs prove --reviewed"}}' >"$OUT_FILE"
assert_eq "Namespaced exec-command cmd field starts proof" "proof:started" \
    "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
for command in "pytest" "cargo test" "go test ./..."; do
    run_adapter "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}" >"$OUT_FILE"
    assert_eq "Unfiltered direct runner starts full verification: $command" "full_test:started" \
        "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
done
for command in \
    "pytest -q" \
    "pytest --maxfail 1" \
    "cargo test --all" \
    "cargo test --features integration" \
    "go test -count=1 ./..." \
    "go test -count 1 ./..." \
    "node --test --test-reporter=spec" \
    "node --test --test-reporter spec"; do
    run_adapter "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}" >"$OUT_FILE"
    assert_eq "Runner-wide direct options stay full verification: $command" "full_test:started" \
        "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
done
for command in "pytest tests/example_test.py" "cargo test journey_transition" "go test ./engine"; do
    run_adapter "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}" >"$OUT_FILE"
    assert_eq "Filtered direct runner starts targeted verification: $command" "targeted_test:started" \
        "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
done
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"functions.exec_command","tool_input":{"cmd":"node --test"}}' >"$OUT_FILE"
assert_eq "Bare Node test runner starts full verification" "full_test:started" \
    "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"functions.exec_command","tool_input":{"cmd":"node --test tests/example.test.js"}}' >"$OUT_FILE"
assert_eq "Filtered Node test runner starts targeted verification" "targeted_test:started" \
    "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
for command in "sed -i '' 's/old/new/' src/app.js" "npx prettier --write src/app.js" "cat <<'EOF' > src/app.js\nchanged\nEOF"; do
    payload=$(jq -cn --arg command "$command" '{hook_event_name:"PreToolUse",session_id:"codex-session",tool_name:"functions.exec_command",tool_input:{cmd:$command}}')
    run_adapter "$payload" >"$OUT_FILE"
    assert_eq "Foreground shell write invalidates later gates: ${command%%$'\n'*}" "implement:started" \
        "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
done
for command in "sed -i '' 's/old/new/' tests/example.test.js" "npx prettier --write tests/example.test.js" "cat <<'EOF' > tests/example.test.js\nchanged\nEOF"; do
    payload=$(jq -cn --arg command "$command" '{hook_event_name:"PreToolUse",session_id:"codex-session",tool_name:"functions.exec_command",tool_input:{cmd:$command}}')
    run_adapter "$payload" >"$OUT_FILE"
    assert_eq "Test-only shell write returns to TDD RED: ${command%%$'\n'*}" "tdd_red:started" \
        "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
done
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","turn_id":"same-turn","tool_use_id":"call-a","tool_name":"Bash","tool_input":{"command":"npm test"}}' >"$OUT_FILE"
operation_a=$(last_event_field '.journey_operation_key')
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","turn_id":"same-turn","tool_use_id":"call-b","tool_name":"Bash","tool_input":{"command":"npm test"}}' >"$OUT_FILE"
operation_b=$(last_event_field '.journey_operation_key')
assert_eq "Concurrent identical tools use distinct operation keys" "true" "$([ "$operation_a" != "$operation_b" ] && printf true || printf false)"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"}}' >"$OUT_FILE"
assert_eq "Review command starts final review" "final_review:started" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"tool_response":{"exit_code":0,"output":"No findings."}}' >"$OUT_FILE"
assert_eq "Explicitly clean review completes final review" "final_review:passed" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"tool_response":{"exit_code":0,"output":"[P1] Fix incorrect rollback"}}' >"$OUT_FILE"
assert_eq "Successful review command with findings emits rollback evidence" "final_review:finding" \
    "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"functions.exec_command","tool_input":{"cmd":"codex review --uncommitted"},"tool_response":{"exit_code":0,"output":"{\"findings\":[{\"title\":\"[P1] Fix rollback\"}]}"}}' >"$OUT_FILE"
assert_eq "Serialized review findings emit rollback evidence" "final_review:finding" \
    "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"functions.exec_command","tool_input":{"cmd":"codex review --uncommitted"},"tool_response":{"exit_code":0,"content":[{"type":"text","text":"{\"findings\":[]}"}]}}' >"$OUT_FILE"
assert_eq "Serialized clean review completes final review" "final_review:passed" \
    "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Ambiguous successful review cannot claim a clean gate" "absent" \
    "$(last_event_field 'if has("journey_checkpoint") then "present" else "absent" end')"
assert_eq "Ambiguous terminal review retires its operation marker" "true" \
    "$(last_event_field '.journey_terminal')"
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"node .codex/hooks/git-guard.cjs prove --reviewed"}}' >"$OUT_FILE"
assert_eq "Proof command starts the proof checkpoint" "proof:started" "$(last_event_field '[.journey_checkpoint,.journey_outcome] | join(":")')"
run_adapter '{"hook_event_name":"PostToolUse","session_id":"codex-session","tool_name":"Bash","tool_input":{"command":"./visualhud journey set proof failed --profile sdlc"},"tool_response":{"exit_code":0}}' >"$OUT_FILE"
assert_eq "Explicit journey CLI evidence is not reinterpreted by its shell hook" "absent" \
    "$(last_event_field 'if has("journey_checkpoint") then "present" else "absent" end')"
for command in "npm install latest" "node scripts/inspect-config.js" "bash scripts/latest-release.sh"; do
    run_adapter "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}" >"$OUT_FILE"
    assert_eq "Non-test command is not classified as targeted verification: $command" "absent" \
        "$(last_event_field 'if has("journey_checkpoint") then "present" else "absent" end')"
done
for command in "npm test || true" "npm test &" "npm test; echo done"; do
    run_adapter "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"codex-session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"},\"tool_response\":{\"exit_code\":0}}" >"$OUT_FILE"
    assert_eq "Masked or detached test cannot emit passing evidence: $command" "absent" \
        "$(last_event_field 'if has("journey_checkpoint") then "present" else "absent" end')"
done
run_adapter '{"hook_event_name":"PreToolUse","session_id":"codex-session","tool_name":"mcp__example__query","tool_input":{"query":"test suite"}}' >"$OUT_FILE"
assert_eq "Non-shell tools cannot become test checkpoints from input text" "absent" \
    "$(last_event_field 'if has("journey_checkpoint") then "present" else "absent" end')"
echo ""

echo "--- Test 7: Codex hooks register VisualHUD lifecycle events ---"
assert_eq "PreToolUse VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "PermissionRequest VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PermissionRequest[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "UserPromptSubmit VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.UserPromptSubmit[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "Stop VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.Stop[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "PostToolUse VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PostToolUse[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "Unsupported TaskCompleted hook is absent" "false" "$(jq -r '.hooks | has("TaskCompleted")' "$HOOKS_JSON")"
assert_eq "Unsupported CwdChanged hook is absent" "false" "$(jq -r '.hooks | has("CwdChanged")' "$HOOKS_JSON")"
assert_eq "Unsupported PostToolUseFailure hook is absent" "false" "$(jq -r '.hooks | has("PostToolUseFailure")' "$HOOKS_JSON")"
assert_eq "SessionStart VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.SessionStart[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "PreCompact VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PreCompact[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "PostCompact VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PostCompact[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$HOOKS_JSON")"
assert_eq "PreCompact SDLC compact guard resolves from repo root" "true" "$(jq -r 'any(.hooks.PreCompact[]?.hooks[]?; .command == "node \"$(git rev-parse --show-toplevel)/.codex/hooks/compact-guard.cjs\"")' "$HOOKS_JSON")"
assert_eq "PostCompact SDLC compact guard resolves from repo root" "true" "$(jq -r 'any(.hooks.PostCompact[]?.hooks[]?; .command == "node \"$(git rev-parse --show-toplevel)/.codex/hooks/compact-guard.cjs\"")' "$HOOKS_JSON")"
assert_eq "SessionStart SDLC node hook resolves from repo root" "true" "$(jq -r 'any(.hooks.SessionStart[]?.hooks[]?; .command == "node \"$(git rev-parse --show-toplevel)/.codex/hooks/session-start.cjs\"")' "$HOOKS_JSON")"
assert_eq "Legacy Bash session hook is inactive" "false" "$(jq -r 'any(.hooks.SessionStart[]?.hooks[]?; .command | contains("session-start.sh"))' "$HOOKS_JSON")"
assert_eq "Exactly one active git guard is registered" "1" "$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select((.command | contains("git-guard.cjs")) or (.command | contains("bash-guard.sh")))] | length' "$HOOKS_JSON")"
assert_eq "Git guard resolves from repo root" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command == "node \"$(git rev-parse --show-toplevel)/.codex/hooks/git-guard.cjs\"")' "$HOOKS_JSON")"
echo ""

echo "--- Test 8: Codex config uses current hooks feature flag ---"
assert_eq "Deprecated codex_hooks flag is absent" "false" "$(grep -Eq '^[[:space:]]*codex_hooks[[:space:]]*=' "$CONFIG_TOML" && printf true || printf false)"
assert_eq "Current hooks feature flag is enabled" "true" "$(grep -Eq '^[[:space:]]*hooks[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$CONFIG_TOML" && printf true || printf false)"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
