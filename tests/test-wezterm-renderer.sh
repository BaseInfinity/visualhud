#!/bin/bash
# WezTerm renderer smoke test. This intentionally avoids jq.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/visualhud"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-wezterm.XXXXXX")"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf "FAIL: %s (expected '%s')\n" "$label" "$needle" >&2
        printf "Actual: %s\n" "$haystack" >&2
        exit 1
    fi
    printf "PASS: %s\n" "$label"
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf "FAIL: %s (did not expect '%s')\n" "$label" "$needle" >&2
        exit 1
    fi
    printf "PASS: %s\n" "$label"
}

assert_file_exists() {
    local label="$1" filepath="$2"
    if [ ! -f "$filepath" ]; then
        printf "FAIL: %s (missing %s)\n" "$label" "$filepath" >&2
        exit 1
    fi
    printf "PASS: %s\n" "$label"
}

assert_path_absent() {
    local label="$1" filepath="$2"
    if [ -e "$filepath" ]; then
        printf "FAIL: %s (unexpected %s)\n" "$label" "$filepath" >&2
        exit 1
    fi
    printf "PASS: %s\n" "$label"
}

latest_wezterm_state() {
    node -e 'const fs=require("fs"); const text=fs.readFileSync(0,"utf8"); const values=[...text.matchAll(/SetUserVar=visualhudState=([A-Za-z0-9+/=]+)/g)]; if (!values.length) process.exit(2); process.stdout.write(Buffer.from(values.at(-1)[1], "base64").toString("utf8"));' < "$1"
}

wait_for_wezterm_state() {
    local filepath="$1" attempt=0
    while ! grep -q 'SetUserVar=visualhudState=' "$filepath" 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 200 ]; then
            printf "FAIL: Timed out waiting for initial WezTerm frame\n" >&2
            exit 1
        fi
        sleep 0.01
    done
}

wait_for_repaint_attempt() {
    local filepath="$1" attempt=0
    while [ ! -s "$filepath" ]; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 200 ]; then
            printf "FAIL: Timed out waiting for stale repaint attempt\n" >&2
            exit 1
        fi
        sleep 0.01
    done
}

wait_for_file_content() {
    local filepath="$1" label="$2" attempt=0
    while [ ! -s "$filepath" ]; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 200 ]; then
            printf "FAIL: Timed out waiting for %s\n" "$label" >&2
            exit 1
        fi
        sleep 0.01
    done
}

wait_for_process_exit() {
    local pid="$1" label="$2" attempt=0
    while kill -0 "$pid" 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 200 ]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            printf "FAIL: Timed out waiting for %s\n" "$label" >&2
            exit 1
        fi
        sleep 0.01
    done
    wait "$pid"
}

echo "=== Test Suite: WezTerm renderer ==="

target="$TMP_ROOT/repo"
mkdir -p "$target"
git -C "$target" init -q

install_output="$(bash "$CLI" install codex --target "$target" --platform wezterm --theme tmnt)"
assert_contains "WezTerm install reports renderer" "Renderer: WezTerm" "$install_output"
assert_file_exists "Installed WezTerm setup script is copied" "$target/.visualhud/setup-wezterm.ps1"
assert_file_exists "Installed WezTerm Lua module is copied" "$target/.visualhud/wezterm/visualhud.lua"
assert_contains "Wrapper pins WezTerm renderer" 'VISUALHUD_RENDERER="wezterm"' "$(cat "$target/.codex/hooks/visualhud-codex.sh")"

TTY_LOG="$TMP_ROOT/tty.log"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-test"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" bash .codex/hooks/visualhud-codex.sh
)

tty_output="$(cat "$TTY_LOG")"
assert_contains "WezTerm renderer names the coarse journey checkpoint" "UNDERSTAND" "$tty_output"
assert_contains "WezTerm renderer emits state user var" "SetUserVar=visualhudState=" "$tty_output"
assert_not_contains "WezTerm renderer avoids Windows Terminal progress OSC" "]9;4;" "$tty_output"
initial_state="$(latest_wezterm_state "$TTY_LOG")"
assert_contains "WezTerm initial state is a task journey" '"state_kind":"journey"' "$initial_state"
assert_contains "WezTerm initial journey starts at checkpoint one" '"stage":"1"' "$initial_state"
assert_contains "WezTerm initial journey reports one of six checkpoints" '"progress_percent":16' "$initial_state"

: > "$TTY_LOG"
REPAINT_ATTEMPT_LOG="$TMP_ROOT/stale-repaint-attempt.log"
REPAINT_RETRY_STARTED="$TMP_ROOT/stale-repaint-retry-started"
REPAINT_RETRY_RELEASE="$TMP_ROOT/release-stale-repaint-retry"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"session_id":"wez-review"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" bash .codex/hooks/visualhud-codex.sh
)
review_state="$(latest_wezterm_state "$TTY_LOG")"
assert_contains "WezTerm review is the fifth coarse checkpoint" '"state_kind":"journey"' "$review_state"
assert_contains "WezTerm review journey reports checkpoint five" '"stage":"5"' "$review_state"
assert_contains "WezTerm review journey reports five of six checkpoints" '"progress_percent":83' "$review_state"
assert_contains "WezTerm Lua formats task journeys as determinate progress" "or state.state_kind == 'journey'" "$(cat "$target/.visualhud/wezterm/visualhud.lua")"

pane_state="$TMP_ROOT/pane-state"
alias_target="$TMP_ROOT/shared-target.log"
for pane_id in pane-a pane-b; do
    (
        cd "$target"
        printf '%s\n' "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"session_id\":\"$pane_id\"}" \
            | env -u WT_SESSION ITERM_SESSION_ID="inherited-iterm" WEZTERM_PANE="$pane_id" \
                VISUALHUD_STATE_DIR="$pane_state" VISUALHUD_TTY="$alias_target" bash .codex/hooks/visualhud-codex.sh
    )
done
pane_token_count="$(find "$pane_state" -type f -name 'visualhud-repaint-target_*' | wc -l | tr -d ' ')"
assert_contains "Stable pane identifiers isolate repaint cancellation" "2" "$pane_token_count"

DELAYED_JSON_HELPER="$TMP_ROOT/delayed-visualhud-json.js"
EVENT_NAME_STARTED="$TMP_ROOT/older-event-name-started"
EVENT_NAME_RELEASE="$TMP_ROOT/release-older-event-name"
FAILED_EARLY_STARTED="$TMP_ROOT/failed-early-event-name-started"
FAILED_EARLY_RELEASE="$TMP_ROOT/release-failed-early-event-name"
TRANSLATION_STARTED="$TMP_ROOT/older-translation-started"
TRANSLATION_RELEASE="$TMP_ROOT/release-older-translation"
RENDER_STARTED="$TMP_ROOT/older-render-started"
RENDER_RELEASE="$TMP_ROOT/release-older-render"
cat > "$DELAYED_JSON_HELPER" <<'EOF'
const fs = require("fs");
const { spawnSync } = require("child_process");

const input = fs.readFileSync(0, "utf8");
function waitForRelease(startedPath, releasePath) {
  fs.writeFileSync(startedPath, "started\n");
  const deadline = Date.now() + 5000;
  while (!fs.existsSync(releasePath)) {
    if (Date.now() >= deadline) {
      process.stderr.write(`Timed out waiting for ${releasePath}\n`);
      process.exit(3);
    }
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 10);
  }
}

if (
  process.argv[2] === "event-name"
    && (
      input.includes('"session_id":"wez-older-event-name"')
      || input.includes('"session_id":"wez-failed-early"')
      || input.includes('"session_id":"wez-recovered-unguarded"')
    )
) {
  waitForRelease(
    input.includes('"session_id":"wez-failed-early"')
      ? process.env.VISUALHUD_TEST_FAILED_EARLY_STARTED
      : process.env.VISUALHUD_TEST_EVENT_NAME_STARTED,
    input.includes('"session_id":"wez-failed-early"')
      ? process.env.VISUALHUD_TEST_FAILED_EARLY_RELEASE
      : process.env.VISUALHUD_TEST_EVENT_NAME_RELEASE,
  );
}
if (
  process.argv[2] === "codex-payload"
  && (
    input.includes('"session_id":"wez-older-translation"')
    || input.includes('"session_id":"wez-delayed-subagent"')
    || input.includes('"session_id":"wez-old-subagent-stop"')
  )
) {
  waitForRelease(
    process.env.VISUALHUD_TEST_TRANSLATION_STARTED,
    process.env.VISUALHUD_TEST_TRANSLATION_RELEASE,
  );
}
if (
  process.argv[2] === "field"
  && process.argv[3] === "source_event"
  && input.includes('"session_id":"wez-older-render"')
) {
  waitForRelease(
    process.env.VISUALHUD_TEST_RENDER_STARTED,
    process.env.VISUALHUD_TEST_RENDER_RELEASE,
  );
}
const result = spawnSync(process.execPath, [process.env.VISUALHUD_REAL_JSON_HELPER, ...process.argv.slice(2)], {
  input,
  encoding: "utf8",
});
process.stdout.write(result.stdout || "");
process.stderr.write(result.stderr || "");
process.exit(result.status == null ? 1 : result.status);
EOF

: > "$TTY_LOG"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-older-event-name"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" \
            VISUALHUD_JSON_HELPER="$DELAYED_JSON_HELPER" VISUALHUD_REAL_JSON_HELPER="$ROOT_DIR/scripts/visualhud-json.js" \
            VISUALHUD_TEST_EVENT_NAME_STARTED="$EVENT_NAME_STARTED" VISUALHUD_TEST_EVENT_NAME_RELEASE="$EVENT_NAME_RELEASE" \
            bash .codex/hooks/visualhud-codex.sh
) &
older_event_name_pid=$!
wait_for_file_content "$EVENT_NAME_STARTED" "older raw-event classification"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"session_id":"wez-newer-than-event-name"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" \
            bash .codex/hooks/visualhud-codex.sh
)
touch "$EVENT_NAME_RELEASE"
wait "$older_event_name_pid"
event_name_collision_state="$(latest_wezterm_state "$TTY_LOG")"
assert_contains "Older raw-event parsing cannot reclaim a newer pane frame" '"stage":"5"' "$event_name_collision_state"

FAILED_EARLY_STATE="$TMP_ROOT/failed-early-state"
FAILED_EARLY_TTY="$TMP_ROOT/failed-early-tty.log"
mkdir -p "$FAILED_EARLY_STATE"
env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
    VISUALHUD_RENDERER=wezterm VISUALHUD_STATE_DIR="$FAILED_EARLY_STATE" VISUALHUD_TTY="$FAILED_EARLY_TTY" \
    bash "$target/.visualhud/engine.sh" --register-repaint >/dev/null
FAILED_EARLY_CLAIM="$(find "$FAILED_EARLY_STATE" -type f -name 'visualhud-repaint-target_*' -print -quit)"
rm -f "$FAILED_EARLY_CLAIM"
mkdir "$FAILED_EARLY_CLAIM"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-failed-early"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$FAILED_EARLY_STATE" VISUALHUD_TTY="$FAILED_EARLY_TTY" \
            VISUALHUD_JSON_HELPER="$DELAYED_JSON_HELPER" VISUALHUD_REAL_JSON_HELPER="$ROOT_DIR/scripts/visualhud-json.js" \
            VISUALHUD_TEST_FAILED_EARLY_STARTED="$FAILED_EARLY_STARTED" \
            VISUALHUD_TEST_FAILED_EARLY_RELEASE="$FAILED_EARLY_RELEASE" \
            bash .codex/hooks/visualhud-codex.sh
) &
failed_early_pid=$!
wait_for_file_content "$FAILED_EARLY_STARTED" "failed early claim classification"
rm -rf "$FAILED_EARLY_CLAIM"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"session_id":"wez-newer-after-failed-early"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$FAILED_EARLY_STATE" VISUALHUD_TTY="$FAILED_EARLY_TTY" \
            bash .codex/hooks/visualhud-codex.sh
)
touch "$FAILED_EARLY_RELEASE"
wait "$failed_early_pid"
failed_early_state="$(latest_wezterm_state "$FAILED_EARLY_TTY")"
assert_contains "A failed early claim cannot reclaim after parsing" '"stage":"5"' "$failed_early_state"

: > "$TTY_LOG"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-older-translation"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" \
            VISUALHUD_JSON_HELPER="$DELAYED_JSON_HELPER" VISUALHUD_REAL_JSON_HELPER="$ROOT_DIR/scripts/visualhud-json.js" \
            VISUALHUD_TEST_TRANSLATION_STARTED="$TRANSLATION_STARTED" VISUALHUD_TEST_TRANSLATION_RELEASE="$TRANSLATION_RELEASE" \
            bash .codex/hooks/visualhud-codex.sh
) &
older_translation_pid=$!
wait_for_file_content "$TRANSLATION_STARTED" "older adapter translation"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"session_id":"wez-newer-translation"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" \
            bash .codex/hooks/visualhud-codex.sh
)
touch "$TRANSLATION_RELEASE"
wait "$older_translation_pid"
translation_collision_state="$(latest_wezterm_state "$TTY_LOG")"
assert_contains "Older adapter translation cannot reclaim a newer pane frame" '"stage":"5"' "$translation_collision_state"

SUBAGENT_STATE="$TMP_ROOT/subagent-translation-state"
: > "$TTY_LOG"
rm -f "$TRANSLATION_STARTED" "$TRANSLATION_RELEASE"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"SubagentStart","agent_id":"delayed-agent","agent_type":"Review","session_id":"wez-delayed-subagent"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$SUBAGENT_STATE" VISUALHUD_TTY="$TTY_LOG" \
            VISUALHUD_JSON_HELPER="$DELAYED_JSON_HELPER" VISUALHUD_REAL_JSON_HELPER="$ROOT_DIR/scripts/visualhud-json.js" \
            VISUALHUD_TEST_TRANSLATION_STARTED="$TRANSLATION_STARTED" VISUALHUD_TEST_TRANSLATION_RELEASE="$TRANSLATION_RELEASE" \
            bash .codex/hooks/visualhud-codex.sh
) &
delayed_subagent_pid=$!
wait_for_file_content "$TRANSLATION_STARTED" "delayed subagent translation"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-newer-than-subagent"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$SUBAGENT_STATE" VISUALHUD_TTY="$TTY_LOG" \
            bash .codex/hooks/visualhud-codex.sh
)
touch "$TRANSLATION_RELEASE"
wait "$delayed_subagent_pid"
subagent_marker_count=0
if [ -d "$SUBAGENT_STATE/claude-cooking-subagent_wez-delayed-subagent.d" ]; then
    subagent_marker_count="$(find "$SUBAGENT_STATE/claude-cooking-subagent_wez-delayed-subagent.d" -type f | wc -l | tr -d ' ')"
fi
assert_contains "Superseded adapter translation preserves lifecycle state" "1" "$subagent_marker_count"
subagent_collision_state="$(latest_wezterm_state "$TTY_LOG")"
assert_contains "Superseded state mutation cannot repaint the newer frame" '"stage":"1"' "$subagent_collision_state"

CROSS_SESSION_STATE="$TMP_ROOT/cross-session-subagent-state"
CROSS_SESSION_TTY="$TMP_ROOT/cross-session-subagent-tty.log"
OLD_STOP_STARTED="$TMP_ROOT/old-subagent-stop-started"
OLD_STOP_RELEASE="$TMP_ROOT/release-old-subagent-stop"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"SubagentStart","agent_id":"old-agent","agent_type":"Review","session_id":"wez-old-subagent-stop"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$CROSS_SESSION_STATE" VISUALHUD_TTY="$CROSS_SESSION_TTY" \
            bash .codex/hooks/visualhud-codex.sh
)
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"SubagentStop","agent_id":"old-agent","session_id":"wez-old-subagent-stop"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$CROSS_SESSION_STATE" VISUALHUD_TTY="$CROSS_SESSION_TTY" \
            VISUALHUD_JSON_HELPER="$DELAYED_JSON_HELPER" VISUALHUD_REAL_JSON_HELPER="$ROOT_DIR/scripts/visualhud-json.js" \
            VISUALHUD_TEST_TRANSLATION_STARTED="$OLD_STOP_STARTED" VISUALHUD_TEST_TRANSLATION_RELEASE="$OLD_STOP_RELEASE" \
            bash .codex/hooks/visualhud-codex.sh
) &
old_stop_pid=$!
wait_for_file_content "$OLD_STOP_STARTED" "old-session subagent stop translation"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"SubagentStart","agent_id":"new-agent","agent_type":"Review","session_id":"wez-new-subagent-start"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$CROSS_SESSION_STATE" VISUALHUD_TTY="$CROSS_SESSION_TTY" \
            bash .codex/hooks/visualhud-codex.sh
)
touch "$OLD_STOP_RELEASE"
wait "$old_stop_pid"
cross_session_state="$(latest_wezterm_state "$CROSS_SESSION_TTY")"
assert_contains "An old session cannot reclaim a newer subagent frame" '"state_kind":"subagent"' "$cross_session_state"

SAME_PANE_STATE="$TMP_ROOT/same-pane-session-state"
SAME_PANE_TTY="$TMP_ROOT/same-pane-session-tty.log"
for payload_session in codex-session-old codex-session-new; do
    (
        cd "$target"
        printf '%s\n' "{\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$payload_session\",\"agent_type\":\"Review\",\"session_id\":\"$payload_session\"}" \
            | env -u ITERM_SESSION_ID -u WT_SESSION WEZTERM_PANE="shared-native-pane" \
                VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
                VISUALHUD_STATE_DIR="$SAME_PANE_STATE" VISUALHUD_TTY="$SAME_PANE_TTY" \
                bash .codex/hooks/visualhud-codex.sh
    )
done
SAME_PANE_CLAIM="$(find "$SAME_PANE_STATE" -type f -name 'visualhud-repaint-target_*' -print -quit)"
assert_contains "Same-pane reconciliation records the payload session" \
    $'SubagentStart\tcodex-session-new' "$(cat "$SAME_PANE_CLAIM")"

: > "$TTY_LOG"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-older-render"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" \
            VISUALHUD_JSON_HELPER="$DELAYED_JSON_HELPER" VISUALHUD_REAL_JSON_HELPER="$ROOT_DIR/scripts/visualhud-json.js" \
            VISUALHUD_TEST_RENDER_STARTED="$RENDER_STARTED" VISUALHUD_TEST_RENDER_RELEASE="$RENDER_RELEASE" \
            bash .codex/hooks/visualhud-codex.sh
) &
older_render_pid=$!
wait_for_file_content "$RENDER_STARTED" "older engine render"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"session_id":"wez-newer-render"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" \
            bash .codex/hooks/visualhud-codex.sh
)
touch "$RENDER_RELEASE"
wait "$older_render_pid"
render_collision_state="$(latest_wezterm_state "$TTY_LOG")"
assert_contains "Older engine work cannot overwrite a newer pane frame" '"stage":"5"' "$render_collision_state"

: > "$TTY_LOG"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-stale"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAYS="0.01" VISUALHUD_TEST_REPAINT_ATTEMPT_FILE="$REPAINT_ATTEMPT_LOG" \
            VISUALHUD_TEST_REPAINT_RETRY_STARTED="$REPAINT_RETRY_STARTED" \
            VISUALHUD_TEST_REPAINT_RETRY_RELEASE="$REPAINT_RETRY_RELEASE" \
            VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" bash .codex/hooks/visualhud-codex.sh
) &
stale_pid=$!
wait_for_wezterm_state "$TTY_LOG"
wait_for_file_content "$REPAINT_RETRY_STARTED" "stale repaint retry"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"session_id":"wez-current"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAYS="0.05" VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" bash .codex/hooks/visualhud-codex.sh
)
touch "$REPAINT_RETRY_RELEASE"
wait "$stale_pid"
wait_for_repaint_attempt "$REPAINT_ATTEMPT_LOG"
repaint_attempt="$(cat "$REPAINT_ATTEMPT_LOG")"
assert_contains "Stale WezTerm retry is explicitly superseded (outcome: $repaint_attempt)" "superseded" "$repaint_attempt"
collision_state="$(latest_wezterm_state "$TTY_LOG")"
assert_contains "Newest WezTerm frame wins across changing session identifiers" '"stage":"5"' "$collision_state"

: > "$TTY_LOG"
ATOMIC_EMIT_STARTED="$TMP_ROOT/atomic-emit-started"
ATOMIC_EMIT_RELEASE="$TMP_ROOT/release-atomic-emit"
ATOMIC_CONTENDER_WAITING="$TMP_ROOT/atomic-contender-waiting"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-atomic-older"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" \
            VISUALHUD_TEST_REPAINT_EMIT_STARTED="$ATOMIC_EMIT_STARTED" \
            VISUALHUD_TEST_REPAINT_EMIT_RELEASE="$ATOMIC_EMIT_RELEASE" \
            bash .codex/hooks/visualhud-codex.sh
) &
atomic_older_pid=$!
wait_for_file_content "$ATOMIC_EMIT_STARTED" "older owned frame"
ATOMIC_LOCK_PATH="$(find "$TMP_ROOT/state" -name 'visualhud-repaint-target_*.lock' -print -quit)"
assert_file_exists "Published repaint lock is one initialized owner record" "$ATOMIC_LOCK_PATH"
assert_contains "Published repaint lock records its owner atomically" ":" "$(cat "$ATOMIC_LOCK_PATH")"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"session_id":"wez-atomic-newer"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" \
            VISUALHUD_TEST_REPAINT_LOCK_CONTENDED="$ATOMIC_CONTENDER_WAITING" \
            bash .codex/hooks/visualhud-codex.sh
) &
atomic_newer_pid=$!
wait_for_file_content "$ATOMIC_CONTENDER_WAITING" "newer atomic-frame contender"
touch "$ATOMIC_EMIT_RELEASE"
wait "$atomic_older_pid"
wait "$atomic_newer_pid"
atomic_collision_state="$(latest_wezterm_state "$TTY_LOG")"
assert_contains "Pane ownership covers the complete terminal frame" '"stage":"5"' "$atomic_collision_state"

UNWRITABLE_STATE="$TMP_ROOT/claim-fallback-state"
FALLBACK_TTY="$TMP_ROOT/fallback-tty.log"
mkdir -p "$UNWRITABLE_STATE"
env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
    VISUALHUD_RENDERER=wezterm VISUALHUD_STATE_DIR="$UNWRITABLE_STATE" VISUALHUD_TTY="$FALLBACK_TTY" \
    bash "$target/.visualhud/engine.sh" --register-repaint >/dev/null
CLAIM_PATH="$(find "$UNWRITABLE_STATE" -type f -name 'visualhud-repaint-target_*' -print -quit)"
rm -f "$CLAIM_PATH"
mkdir "$CLAIM_PATH"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-claim-fallback"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$UNWRITABLE_STATE" VISUALHUD_TTY="$FALLBACK_TTY" \
            bash .codex/hooks/visualhud-codex.sh
)
fallback_state="$(latest_wezterm_state "$FALLBACK_TTY")"
assert_contains "Claim persistence failure keeps best-effort rendering" '"state_kind":"working"' "$fallback_state"

RECOVERED_STATE="$TMP_ROOT/recovered-unguarded-state"
RECOVERED_TTY="$TMP_ROOT/recovered-unguarded-tty.log"
UNGUARDED_EMIT_STARTED="$TMP_ROOT/unguarded-emit-started"
UNGUARDED_EMIT_RELEASE="$TMP_ROOT/release-unguarded-emit"
UNGUARDED_CONTENDER_WAITING="$TMP_ROOT/unguarded-contender-waiting"
mkdir -p "$RECOVERED_STATE"
env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
    VISUALHUD_RENDERER=wezterm VISUALHUD_STATE_DIR="$RECOVERED_STATE" VISUALHUD_TTY="$RECOVERED_TTY" \
    bash "$target/.visualhud/engine.sh" --register-repaint >/dev/null
RECOVERED_CLAIM="$(find "$RECOVERED_STATE" -type f -name 'visualhud-repaint-target_*' -print -quit)"
rm -f "$RECOVERED_CLAIM" "$EVENT_NAME_STARTED" "$EVENT_NAME_RELEASE"
mkdir "$RECOVERED_CLAIM"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-recovered-unguarded"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$RECOVERED_STATE" VISUALHUD_TTY="$RECOVERED_TTY" \
            VISUALHUD_JSON_HELPER="$DELAYED_JSON_HELPER" VISUALHUD_REAL_JSON_HELPER="$ROOT_DIR/scripts/visualhud-json.js" \
            VISUALHUD_TEST_EVENT_NAME_STARTED="$EVENT_NAME_STARTED" VISUALHUD_TEST_EVENT_NAME_RELEASE="$EVENT_NAME_RELEASE" \
            VISUALHUD_TEST_UNGUARDED_EMIT_STARTED="$UNGUARDED_EMIT_STARTED" \
            VISUALHUD_TEST_UNGUARDED_EMIT_RELEASE="$UNGUARDED_EMIT_RELEASE" \
            bash .codex/hooks/visualhud-codex.sh
) &
unguarded_old_pid=$!
wait_for_file_content "$EVENT_NAME_STARTED" "unguarded event classification"
rm -rf "$RECOVERED_CLAIM"
touch "$EVENT_NAME_RELEASE"
wait_for_file_content "$UNGUARDED_EMIT_STARTED" "recovered unguarded frame"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"session_id":"wez-newer-after-recovery"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$RECOVERED_STATE" VISUALHUD_TTY="$RECOVERED_TTY" \
            VISUALHUD_TEST_REPAINT_LOCK_CONTENDED="$UNGUARDED_CONTENDER_WAITING" \
            bash .codex/hooks/visualhud-codex.sh
) &
unguarded_new_pid=$!
wait_for_file_content "$UNGUARDED_CONTENDER_WAITING" "newer recovered-storage contender"
touch "$UNGUARDED_EMIT_RELEASE"
wait "$unguarded_old_pid" "$unguarded_new_pid"
recovered_collision_state="$(latest_wezterm_state "$RECOVERED_TTY")"
assert_contains "Recovered unguarded frame is serialized before a newer owner" \
    '"state_kind":"review"' "$recovered_collision_state"

UNGUARDED_RETRY_TTY="$TMP_ROOT/unguarded-retry-tty.log"
: > "$UNGUARDED_RETRY_TTY"
UNGUARDED_TARGET_CHECKSUM=$(printf 'target:%s' "$UNGUARDED_RETRY_TTY" | cksum)
UNGUARDED_TARGET_KEY=${UNGUARDED_TARGET_CHECKSUM%% *}
mkdir "$UNWRITABLE_STATE/visualhud-repaint-target_$UNGUARDED_TARGET_KEY"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-unguarded-retry"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAYS=0.01 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$UNWRITABLE_STATE" VISUALHUD_TTY="$UNGUARDED_RETRY_TTY" \
            bash .codex/hooks/visualhud-codex.sh
)
sleep 0.1
unguarded_frame_count="$(grep -o 'SetUserVar=visualhudState=' "$UNGUARDED_RETRY_TTY" 2>/dev/null | wc -l | tr -d ' ')"
assert_contains "Unguarded fallback emits only its initial frame" "1" "$unguarded_frame_count"

LIVE_LOCK_STATE="$TMP_ROOT/live-lock-state"
LIVE_LOCK_TTY="$TMP_ROOT/live-lock-tty.log"
mkdir -p "$LIVE_LOCK_STATE"
env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
    VISUALHUD_RENDERER=wezterm VISUALHUD_STATE_DIR="$LIVE_LOCK_STATE" VISUALHUD_TTY="$LIVE_LOCK_TTY" \
    bash "$target/.visualhud/engine.sh" --register-repaint >/dev/null
LIVE_LOCK_CLAIM="$(find "$LIVE_LOCK_STATE" -type f -name 'visualhud-repaint-target_*' -print -quit)"
printf '%s' "$$:live" > "${LIVE_LOCK_CLAIM}.lock"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-live-lock"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$LIVE_LOCK_STATE" VISUALHUD_TTY="$LIVE_LOCK_TTY" \
            bash .codex/hooks/visualhud-codex.sh
)
assert_path_absent "Live lock contention does not create a competing frame" "$LIVE_LOCK_TTY"
rm -f "${LIVE_LOCK_CLAIM}.lock"

MALFORMED_LOCK_STATE="$TMP_ROOT/malformed-lock-state"
MALFORMED_LOCK_TTY="$TMP_ROOT/malformed-lock-tty.log"
mkdir -p "$MALFORMED_LOCK_STATE"
env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
    VISUALHUD_RENDERER=wezterm VISUALHUD_STATE_DIR="$MALFORMED_LOCK_STATE" VISUALHUD_TTY="$MALFORMED_LOCK_TTY" \
    bash "$target/.visualhud/engine.sh" --register-repaint >/dev/null
MALFORMED_LOCK_CLAIM="$(find "$MALFORMED_LOCK_STATE" -type f -name 'visualhud-repaint-target_*' -print -quit)"
printf '%s' 'corrupt:value' > "${MALFORMED_LOCK_CLAIM}.lock"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-malformed-lock"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$MALFORMED_LOCK_STATE" VISUALHUD_TTY="$MALFORMED_LOCK_TTY" \
            bash .codex/hooks/visualhud-codex.sh
) &
malformed_lock_pid=$!
wait_for_process_exit "$malformed_lock_pid" "malformed repaint-lock recovery"
malformed_lock_state="$(latest_wezterm_state "$MALFORMED_LOCK_TTY")"
assert_contains "Malformed repaint lock is reclaimed without suppressing the HUD" \
    '"state_kind":"working"' "$malformed_lock_state"

ORPHAN_STATE="$TMP_ROOT/orphan-lock-state"
ORPHAN_TTY="$TMP_ROOT/orphan-lock-tty.log"
mkdir -p "$ORPHAN_STATE"
env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
    VISUALHUD_RENDERER=wezterm VISUALHUD_STATE_DIR="$ORPHAN_STATE" VISUALHUD_TTY="$ORPHAN_TTY" \
    bash "$target/.visualhud/engine.sh" --register-repaint >/dev/null
ORPHAN_CLAIM="$(find "$ORPHAN_STATE" -type f -name 'visualhud-repaint-target_*' -print -quit)"
mkdir "${ORPHAN_CLAIM}.lock"
touch "${ORPHAN_CLAIM}.lock/not-owned-by-visualhud"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-orphan-lock"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$ORPHAN_STATE" VISUALHUD_TTY="$ORPHAN_TTY" \
            bash .codex/hooks/visualhud-codex.sh
) &
orphan_lock_pid=$!
wait_for_process_exit "$orphan_lock_pid" "ownerless repaint-lock recovery"
orphan_lock_state="$(latest_wezterm_state "$ORPHAN_TTY")"
assert_contains "Ownerless repaint lock is reclaimed without suppressing the HUD" '"state_kind":"working"' "$orphan_lock_state"
assert_file_exists "Unowned repaint-lock data is not recursively deleted" "${ORPHAN_CLAIM}.lock/not-owned-by-visualhud"

FAKE_TTY_BIN="$TMP_ROOT/fake-tty-bin"
PARENT_TTY_STATE="$TMP_ROOT/parent-tty-state"
mkdir -p "$FAKE_TTY_BIN" "$PARENT_TTY_STATE"
cat > "$FAKE_TTY_BIN/tty" <<'EOF'
#!/bin/sh
printf '/dev/tty\n'
EOF
cat > "$FAKE_TTY_BIN/ps" <<'EOF'
#!/bin/sh
case "$*" in
    *'tty='*) printf '%s\n' "$VISUALHUD_TEST_PARENT_TTY" ;;
    *'ppid='*) printf '1\n' ;;
esac
EOF
chmod +x "$FAKE_TTY_BIN/tty" "$FAKE_TTY_BIN/ps"
for parent_tty in pts/101 pts/102; do
    env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
        PATH="$FAKE_TTY_BIN:$PATH" VISUALHUD_RENDERER=wezterm VISUALHUD_TTY=/dev/tty \
        VISUALHUD_TEST_PARENT_TTY="$parent_tty" VISUALHUD_STATE_DIR="$PARENT_TTY_STATE" \
        bash "$target/.visualhud/engine.sh" --register-repaint >/dev/null
done
parent_tty_claim_count="$(find "$PARENT_TTY_STATE" -type f -name 'visualhud-repaint-target_*' | wc -l | tr -d ' ')"
assert_contains "Concrete parent TTYs keep fallback panes isolated" "2" "$parent_tty_claim_count"

LOOP_TTY="$TMP_ROOT/loop-ownership-tty.log"
LOOP_STATE="$TMP_ROOT/loop-ownership-state"
LOOP_STATUS_STARTED="$TMP_ROOT/loop-status-started"
LOOP_STATUS_RELEASE="$TMP_ROOT/release-loop-status"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"Stop","session_id":"wez-stale-loop"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off VISUALHUD_LOOP_THRESHOLD=1 \
            VISUALHUD_STATE_DIR="$LOOP_STATE" VISUALHUD_TTY="$LOOP_TTY" \
            VISUALHUD_TEST_LOOP_STATUS_STARTED="$LOOP_STATUS_STARTED" \
            VISUALHUD_TEST_LOOP_STATUS_RELEASE="$LOOP_STATUS_RELEASE" \
            bash .codex/hooks/visualhud-codex.sh
) &
stale_loop_pid=$!
wait_for_file_content "$LOOP_STATUS_STARTED" "stale loop status"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"wez-current-after-loop"}' \
        | env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
            VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
            VISUALHUD_STATE_DIR="$LOOP_STATE" VISUALHUD_TTY="$LOOP_TTY" \
            bash .codex/hooks/visualhud-codex.sh
)
touch "$LOOP_STATUS_RELEASE"
wait "$stale_loop_pid"
assert_not_contains "Stale loop status cannot overwrite a newer pane frame" "LOOP DETECTED" "$(cat "$LOOP_TTY")"

echo "=== Results: PASS ==="
