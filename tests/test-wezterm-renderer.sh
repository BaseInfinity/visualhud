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
        | VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" bash .codex/hooks/visualhud-codex.sh
)

tty_output="$(cat "$TTY_LOG")"
assert_contains "WezTerm renderer names the coarse journey checkpoint" "UNDERSTAND" "$tty_output"
assert_contains "WezTerm renderer emits state user var" "SetUserVar=visualhudState=" "$tty_output"
assert_not_contains "WezTerm renderer avoids Windows Terminal progress OSC" "]9;4;" "$tty_output"
initial_state="$(node -e 'const fs=require("fs"); const text=fs.readFileSync(0,"utf8"); const values=[...text.matchAll(/SetUserVar=visualhudState=([A-Za-z0-9+/=]+)/g)]; process.stdout.write(Buffer.from(values.at(-1)[1], "base64").toString("utf8"));' < "$TTY_LOG")"
assert_contains "WezTerm initial state is a task journey" '"state_kind":"journey"' "$initial_state"
assert_contains "WezTerm initial journey starts at checkpoint one" '"stage":"1"' "$initial_state"
assert_contains "WezTerm initial journey reports one of six checkpoints" '"progress_percent":16' "$initial_state"

: > "$TTY_LOG"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"codex review --uncommitted"},"session_id":"wez-review"}' \
        | VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" bash .codex/hooks/visualhud-codex.sh
)
review_state="$(node -e 'const fs=require("fs"); const text=fs.readFileSync(0,"utf8"); const values=[...text.matchAll(/SetUserVar=visualhudState=([A-Za-z0-9+/=]+)/g)]; process.stdout.write(Buffer.from(values.at(-1)[1], "base64").toString("utf8"));' < "$TTY_LOG")"
assert_contains "WezTerm review is the fifth coarse checkpoint" '"state_kind":"journey"' "$review_state"
assert_contains "WezTerm review journey reports checkpoint five" '"stage":"5"' "$review_state"
assert_contains "WezTerm review journey reports five of six checkpoints" '"progress_percent":83' "$review_state"
assert_contains "WezTerm Lua formats task journeys as determinate progress" "or state.state_kind == 'journey'" "$(cat "$target/.visualhud/wezterm/visualhud.lua")"

echo "=== Results: PASS ==="
