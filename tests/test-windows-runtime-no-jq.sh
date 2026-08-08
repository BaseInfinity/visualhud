#!/bin/bash
# Windows/PowerShell renderer smoke test. This intentionally avoids jq.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/visualhud"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-windows.XXXXXX")"

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

assert_file_exists() {
    local label="$1" filepath="$2"
    if [ ! -f "$filepath" ]; then
        printf "FAIL: %s (missing %s)\n" "$label" "$filepath" >&2
        exit 1
    fi
    printf "PASS: %s\n" "$label"
}

echo "=== Test Suite: Windows runtime without jq ==="

if grep -E '\<jq\>' "$ROOT_DIR/engine.sh" "$ROOT_DIR/visualhud" \
    "$ROOT_DIR/.codex/hooks/visualhud-codex.sh" "$ROOT_DIR/.claude/hooks/visualhud-claude.sh" >/dev/null; then
    printf "FAIL: runtime files should not call jq\n" >&2
    exit 1
fi
printf "PASS: runtime files do not call jq\n"

target="$TMP_ROOT/repo"
mkdir -p "$target"
git -C "$target" init -q

install_output="$(bash "$CLI" install codex --target "$target" --platform windows --theme tmnt)"
assert_contains "Windows install reports renderer" "Renderer: Windows Terminal/PowerShell" "$install_output"
assert_file_exists "Installed JSON helper is copied" "$target/.visualhud/scripts/visualhud-json.js"
assert_contains "Wrapper pins Windows renderer" 'VISUALHUD_RENDERER="windows"' "$(cat "$target/.codex/hooks/visualhud-codex.sh")"

TTY_LOG="$TMP_ROOT/tty.log"
(
    cd "$target"
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"win-test"}' \
        | VISUALHUD_STATE_DIR="$TMP_ROOT/state" VISUALHUD_TTY="$TTY_LOG" bash .codex/hooks/visualhud-codex.sh
)

tty_output="$(cat "$TTY_LOG")"
assert_contains "Windows renderer sets semantic title" "WORKING" "$tty_output"
assert_contains "Windows renderer emits indeterminate WORKING progress" "]9;4;3;0" "$tty_output"

echo "=== Results: PASS ==="
