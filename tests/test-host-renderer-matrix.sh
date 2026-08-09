#!/bin/bash
# Deterministic host/renderer compatibility and test-isolation contract.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX="$ROOT_DIR/docs/compatibility-matrix.v1.json"
MATRIX_TOOL="$ROOT_DIR/scripts/visualhud-compatibility.js"
RUN_ALL="$ROOT_DIR/tests/run-all.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-compatibility.XXXXXX")"
PASS=0
FAIL=0
TOTAL=0

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    printf '  PASS: %s\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    printf '  FAIL: %s\n' "$1" >&2
}

assert_file_exists() {
    local label="$1" path="$2"
    if [ -f "$path" ]; then
        pass "$label"
    else
        fail "$label (missing $path)"
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$label"
    else
        fail "$label (missing '$needle')"
    fi
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$actual')"
    fi
}

combination_label() {
    printf 'host=%s renderer=%s event=%s model=%s effort=%s' "$1" "$2" "$3" "$4" "$5"
}

echo "=== Test Suite: host and renderer compatibility matrix ==="
echo ""

echo "--- Test 1: Versioned compatibility contract is valid and reportable ---"
assert_file_exists "Versioned compatibility matrix exists" "$MATRIX"
assert_file_exists "Compatibility validator exists" "$MATRIX_TOOL"

if [ ! -f "$MATRIX" ] || [ ! -f "$MATRIX_TOOL" ]; then
    printf '\n=== Results: %d/%d passed, %d failed ===\n' "$PASS" "$TOTAL" "$FAIL"
    exit 1
fi

if validation_output=$(node "$MATRIX_TOOL" validate 2>&1); then
    pass "Compatibility matrix validates against fixtures and hook registrations"
else
    fail "Compatibility matrix validation failed: $validation_output"
fi

report_output=$(node "$MATRIX_TOOL" report)
readme_doc=$(cat "$ROOT_DIR/README.md")
testing_doc=$(cat "$ROOT_DIR/TESTING.md")
architecture_doc=$(cat "$ROOT_DIR/ARCHITECTURE.md")
assert_contains "Coverage report identifies Codex as a host" "Codex CLI (host)" "$report_output"
assert_contains "Coverage report identifies Sol as a model lane" "gpt-5.6-sol / medium" "$report_output"
assert_contains "Coverage report keeps live lanes supervised" "supervised (#16)" "$report_output"
assert_contains "Coverage report names Windows limitations" "no dynamic background images" "$report_output"
assert_contains "Coverage report forbids paid tests in default CI" "paid/authenticated tests in default CI: no" "$report_output"
for path_case in \
    'Linux|{"cwd":"/home/alice/private/repo"}' \
    'macOS|{"cwd":"/Users/alice/private/repo"}' \
    'Windows|{"cwd":"C:\\Users\\alice\\private\\repo"}'; do
    path_label=${path_case%%|*}
    path_payload=${path_case#*|}
    if printf '%s' "$path_payload" | node "$MATRIX_TOOL" sanitize-check >/dev/null 2>&1; then
        fail "Sanitizer rejects $path_label home-directory identity"
    else
        pass "Sanitizer rejects $path_label home-directory identity"
    fi
done
for credential_key in \
    token refresh_token client_secret api_token session_token private_key \
    refreshToken clientSecret apiKey sessionToken privateKey refresh-token APIKey; do
    if jq -cn --arg key "$credential_key" '{($key): "secret-value"}' | \
        node "$MATRIX_TOOL" sanitize-check >/dev/null 2>&1; then
        fail "Sanitizer rejects credential field $credential_key"
    else
        pass "Sanitizer rejects credential field $credential_key"
    fi
done
for telemetry_key in token_count tokenCount; do
    if jq -cn --arg key "$telemetry_key" '{($key): 1234}' | \
        node "$MATRIX_TOOL" sanitize-check >/dev/null 2>&1; then
        pass "Sanitizer accepts $telemetry_key telemetry"
    else
        fail "Sanitizer accepts $telemetry_key telemetry"
    fi
done
if printf '%s' '{"cwd":".","session_id":"sanitized-fixture"}' | node "$MATRIX_TOOL" sanitize-check >/dev/null 2>&1; then
    pass "Sanitizer accepts synthetic fixture data"
else
    fail "Sanitizer accepts synthetic fixture data"
fi
assert_contains "README separates the Codex host from the Sol model lane" "Codex is the host; GPT-5.6 Sol is a model lane" "$readme_doc"
assert_contains "Testing docs expose the deterministic matrix command" "npm run test:matrix" "$testing_doc"
assert_contains "Testing docs keep the live canary outside npm test" "issue #16" "$testing_doc"
assert_contains "Architecture documents the suite capture boundary" "VISUALHUD_TEST_CAPTURE_DIR" "$architecture_doc"
echo ""

echo "--- Test 2: Sanitized fixtures cover every registered host event ---"
MOCK_ENGINE="$TMP_ROOT/mock-engine.sh"
cat > "$MOCK_ENGINE" <<'EOF'
#!/bin/bash
cat > "$VISUALHUD_TEST_LOG"
printf 'adapter stdout must stay hidden\n'
EOF
chmod +x "$MOCK_ENGINE"

for host in $(jq -r '.hosts[].id' "$MATRIX"); do
    adapter_rel=$(jq -r --arg host "$host" '.hosts[] | select(.id == $host) | .adapter' "$MATRIX")
    fixture_rel=$(jq -r --arg host "$host" '.hosts[] | select(.id == $host) | .fixture' "$MATRIX")
    fixture="$ROOT_DIR/$fixture_rel"
    assert_file_exists "$host sanitized fixture file exists" "$fixture"
    [ -f "$fixture" ] || continue

    while IFS= read -r fixture_case; do
        event=$(printf '%s' "$fixture_case" | jq -r '.id')
        model=$(printf '%s' "$fixture_case" | jq -r '.model')
        effort=$(printf '%s' "$fixture_case" | jq -r '.effort')
        expected=$(printf '%s' "$fixture_case" | jq -r '.expected_event')
        payload=$(printf '%s' "$fixture_case" | jq -c '.payload')
        log="$TMP_ROOT/${host}-${event}.json"
        label=$(combination_label "$host" adapter "$event" "$model" "$effort")

        stdout=$(printf '%s' "$payload" | \
            VISUALHUD_ENGINE="$MOCK_ENGINE" \
            VISUALHUD_TEST_LOG="$log" \
            VISUALHUD_REAPPLY_DELAY=0 \
            bash "$ROOT_DIR/$adapter_rel")
        assert_eq "$label keeps host hook stdout empty" "" "$stdout"
        actual=$(jq -r '.hook_event_name' "$log")
        assert_eq "$label normalizes the expected event" "$expected" "$actual"
    done < <(jq -c '.cases[]' "$fixture")
done
echo ""

echo "--- Test 3: Supported host lifecycle states render semantically everywhere ---"
for host in $(jq -r '.hosts[].id' "$MATRIX"); do
    adapter_rel=$(jq -r --arg host "$host" '.hosts[] | select(.id == $host) | .adapter' "$MATRIX")
    fixture_rel=$(jq -r --arg host "$host" '.hosts[] | select(.id == $host) | .fixture' "$MATRIX")
    fixture="$ROOT_DIR/$fixture_rel"

    while IFS= read -r fixture_case; do
        event=$(printf '%s' "$fixture_case" | jq -r '.id')
        model=$(printf '%s' "$fixture_case" | jq -r '.model')
        effort=$(printf '%s' "$fixture_case" | jq -r '.effort')
        payload=$(printf '%s' "$fixture_case" | jq -c '.payload')
        expected_title=$(printf '%s' "$fixture_case" | jq -r '.render.title')
        expected_kind=$(printf '%s' "$fixture_case" | jq -r '.render.state_kind')
        expected_windows=$(printf '%s' "$fixture_case" | jq -r '.render.windows_state')

        for renderer in iterm2 wezterm windows; do
            case_root="$TMP_ROOT/render-${host}-${renderer}-${event}"
            state_root="$case_root/state"
            tty_log="$case_root/tty.log"
            mkdir -p "$state_root"
            : > "$tty_log"
            label=$(combination_label "$host" "$renderer" "$event" "$model" "$effort")

            stdout=$(printf '%s' "$payload" | \
                env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
                VISUALHUD_ENGINE="$ROOT_DIR/engine.sh" \
                VISUALHUD_RENDERER="$renderer" \
                VISUALHUD_TTY="$tty_log" \
                VISUALHUD_STATE_DIR="$state_root" \
                VISUALHUD_THEME=pokemon \
                VISUALHUD_JOURNEY_PROFILE=off \
                VISUALHUD_ACTIVITY_MODE=semantic \
                VISUALHUD_REAPPLY_DELAY=0 \
                VISUALHUD_BG=off \
                bash "$ROOT_DIR/$adapter_rel")
            output=$(cat "$tty_log")
            assert_eq "$label keeps host hook stdout empty" "" "$stdout"
            assert_contains "$label emits the semantic title" "$expected_title" "$output"

            case "$renderer" in
                iterm2)
                    assert_contains "$label emits an iTerm2 badge" "SetBadgeFormat=" "$output"
                    assert_contains "$label emits an iTerm2 tab color" "SetColors=tab=" "$output"
                    assert_contains "$label emits the iTerm2 HUD title variable" "SetUserVar=hudProgress=" "$output"
                    ;;
                wezterm)
                    assert_contains "$label emits WezTerm state" "SetUserVar=visualhudState=" "$output"
                    wezterm_state=$(node -e 'const fs=require("fs"); const text=fs.readFileSync(0,"utf8"); const values=[...text.matchAll(/SetUserVar=visualhudState=([A-Za-z0-9+/=]+)/g)]; if (!values.length) process.exit(2); process.stdout.write(Buffer.from(values.at(-1)[1], "base64").toString("utf8"));' < "$tty_log")
                    assert_eq "$label reports the semantic state kind" "$expected_kind" "$(printf '%s' "$wezterm_state" | jq -r '.state_kind')"
                    ;;
                windows)
                    assert_contains "$label emits the Windows progress state" "]9;4;${expected_windows};" "$output"
                    ;;
            esac
        done
    done < <(jq -c '.cases[] | select(.render != null)' "$fixture")
done
echo ""

echo "--- Test 4: The default suite cannot target a developer pane ---"
run_all_doc=$(cat "$RUN_ALL")
engine_doc=$(cat "$ROOT_DIR/engine.sh")
assert_contains "Full suite creates a dedicated terminal capture boundary" "VISUALHUD_TEST_CAPTURE_DIR" "$run_all_doc"
assert_contains "Full suite removes inherited iTerm2 identity" "-u ITERM_SESSION_ID" "$run_all_doc"
assert_contains "Full suite removes inherited Windows Terminal identity" "-u WT_SESSION" "$run_all_doc"
assert_contains "Full suite removes inherited WezTerm identity" "-u WEZTERM_PANE" "$run_all_doc"
assert_contains "Engine honors the test capture boundary" "VISUALHUD_TEST_CAPTURE_DIR" "$engine_doc"

if [[ "$engine_doc" == *"VISUALHUD_TEST_CAPTURE_DIR"* ]]; then
    isolated_root="$TMP_ROOT/isolated-runtime"
    mkdir -p "$isolated_root/scripts" "$isolated_root/themes"
    cp "$ROOT_DIR/engine.sh" "$isolated_root/engine.sh"
    cp "$ROOT_DIR/scripts/visualhud-json.js" "$isolated_root/scripts/visualhud-json.js"
    cp -R "$ROOT_DIR/themes/pokemon" "$isolated_root/themes/pokemon"
    cat > "$isolated_root/set_bg.py" <<'PY'
#!/usr/bin/env python3
import os
from pathlib import Path
Path(os.environ["VISUALHUD_ISOLATION_VIOLATION_LOG"]).write_text("called", encoding="utf-8")
PY
    capture_dir="$TMP_ROOT/suite-capture"
    violation_log="$TMP_ROOT/background-api-called"
    mkdir -p "$capture_dir"
    printf '%s' '{"hook_event_name":"PreToolUse","session_id":"developer-pane","tool_name":"Read"}' | \
        env -u VISUALHUD_TTY -u VISUALHUD_SET_BG \
        ITERM_SESSION_ID="w0t0p0:REAL_DEVELOPER_PANE" \
        VISUALHUD_TEST_CAPTURE_DIR="$capture_dir" \
        VISUALHUD_ISOLATION_VIOLATION_LOG="$violation_log" \
        VISUALHUD_STATE_DIR="$TMP_ROOT/isolation-state" \
        VISUALHUD_THEME=pokemon \
        VISUALHUD_JOURNEY_PROFILE=off \
        VISUALHUD_REAPPLY_DELAY=0 \
        VISUALHUD_BG=on \
        bash "$isolated_root/engine.sh"
    assert_file_exists "Isolated engine writes terminal controls only to the suite capture" "$capture_dir/terminal.log"
    if [ -e "$violation_log" ]; then
        fail "Isolated engine invoked the real background helper"
    else
        pass "Isolated engine suppresses the real background helper"
    fi
fi

printf '\n=== Results: %d/%d passed, %d failed ===\n' "$PASS" "$TOTAL" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
